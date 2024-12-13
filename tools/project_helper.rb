# frozen_string_literal: true

require "xcodeproj"
require "json"

action = ARGV[0]
project_path = ARGV[1]

# @type [Xcodeproj::Project]
project = Xcodeproj::Project.open(project_path)

# @type [String]
$pods_cache = []

# @param [String] project_path
# @return [Array<String>]
def find_dev_pod_paths(project_path)
  return $pods_cache unless $pods_cache.empty?

  podfile_path = File.join(File.dirname(File.dirname(project_path).to_s), "Podfile")

  return [] unless File.exist?(podfile_path)

  podfile_json = `pod ipc podfile-json "#{podfile_path}"`
  podfile = JSON.parse(podfile_json)

  paths = []
  podfile["target_definitions"].each do |target|
    target["children"].each do |child|
      child["dependencies"].each do |dependency|
        next unless dependency.is_a?(Hash)

        dependency.each_value do |value|
          next unless value.is_a?(Array)

          value.each do |item|
            if item.is_a?(Hash) && item["path"]
              paths << item["path"].chomp("/")
            end
          end
        end
      end
    end
  end

  $pods_cache = paths.uniq
  $pods_cache
end

# @param [Xcodeproj::Project] project
# @param [String] path
# @param [Boolean] exit_on_not_found
# @return [Xcodeproj::Project::Object::PBXGroup?]
def find_group_by_absolute_file_path(project, path, exit_on_not_found = true)
  dir = File.dirname(path)
  find_group_by_absolute_dir_path(project, dir, exit_on_not_found)
end

# @param [Xcodeproj::Project] project
# @param [String] path
# @param [Boolean] exit_on_not_found
# @return [Xcodeproj::Project::Object::PBXGroup?]
def find_group_by_absolute_dir_path(project, path, exit_on_not_found = true)
  main_group_path = project.main_group.real_path.to_s

  is_pods = main_group_path.end_with? "/Pods"
  if is_pods
    main_group_path = main_group_path.sub("/Pods", "")
  end

  relative_path = path.sub("#{main_group_path}/", "")

  if is_pods && !relative_path.start_with?("/")
    find_dev_pod_paths(project.path.to_s).each do |path|
      next unless path.include?("/")

      pod_basepath = "#{File.dirname(path)}/"
      relative_path = relative_path.sub(pod_basepath, "")
    end
    relative_path = "Development Pods/#{relative_path}"
  end

  result = project[relative_path]

  if result.nil? && exit_on_not_found
    group_name = File.basename(path)
    puts "WARN: xcodebuild.nvim: Could not find \"#{group_name}\" group in the project."
    exit
  end

  result
end

# @param [Xcodeproj::Project] project
# @param [String] file_path
# @param [Boolean] exit_on_not_found
# @return [Xcodeproj::Project::Object::PBXFileReference?]
def find_file(project, file_path, exit_on_not_found = true)
  file_ref = project.files.find { |file| file.real_path.to_s == file_path }

  if file_ref.nil? && exit_on_not_found
    file_name = File.basename(file_path)
    puts "WARN: xcodebuild.nvim: Could not find \"#{file_name}\" in the project."
    exit
  end

  file_ref
end

# @param [Xcodeproj::Project] project
# @param [String] targets
# @param [String] file_path
def add_file_to_targets(project, targets, file_path)
  file_ref = find_file(project, file_path, false)

  if file_ref.nil?
    group = find_group_by_absolute_file_path(project, file_path)
    file_ref = group.new_reference(file_path)
  end

  targets.split(",").each do |target|
    target = project.native_targets.find { |current| current.name == target }
    target.add_file_references([file_ref])
  end

  project.save
end

# @param [Xcodeproj::Project] project
# @param [String] targets
# @param [String] file_path
def update_file_targets(project, targets, file_path)
  find_file(project, file_path).remove_from_project
  add_file_to_targets(project, targets, file_path)
end

# @param [Xcodeproj::Project] project
# @param [String] file_path
def delete_file(project, file_path)
  find_file(project, file_path).remove_from_project
  project.save
end

# @param [Xcodeproj::Project] project
# @param [String] old_file_path
# @param [String] new_file_path
def rename_file(project, old_file_path, new_file_path)
  find_file(project, old_file_path).set_path(new_file_path)
  project.save
end

# @param [Xcodeproj::Project] project
# @param [String] old_path
# @param [String] new_path
def move_file(project, old_path, new_path)
  targets = get_targets_for_file(project, old_path)
  delete_file(project, old_path)
  add_file_to_targets(project, targets.join(","), new_path)
end

# @param [Xcodeproj::Project] project
# @param [String] group_path
def add_group(project, group_path)
  splitted_path = group_path.split("/")

  (1..(splitted_path.length - 2)).each do |i|
    current_path = splitted_path[0..i].join("/")
    new_group_path = "#{current_path}/#{splitted_path[i + 1]}"
    parent_group = find_group_by_absolute_dir_path(project, current_path, false)
    current_group = find_group_by_absolute_dir_path(project, new_group_path, false)

    if current_group.nil? && !parent_group.nil?
      parent_group.new_group(splitted_path[i + 1], new_group_path)
    end
  end

  project.save
end

# @param [Xcodeproj::Project] project
# @param [String] old_group_path
# @param [String] new_group_path
def rename_group(project, old_group_path, new_group_path)
  group = find_group_by_absolute_dir_path(project, old_group_path)
  group.name = File.basename(new_group_path)
  group.set_path(new_group_path)
  project.save
end

# @param [Xcodeproj::Project] project
# @param [String] old_path
# @param [String] new_path
def move_group(project, old_path, new_path)
  new_parent_path = File.dirname(new_path)
  new_parent_group = find_group_by_absolute_dir_path(project, new_parent_path)
  old_group = find_group_by_absolute_dir_path(project, old_path)
  old_group.move(new_parent_group)
  old_group.set_path(new_path)

  project.save
end

# @param [Xcodeproj::Project] project
# @param [String] group_path
def delete_group(project, group_path)
  group = find_group_by_absolute_dir_path(project, group_path)
  group.recursive_children_groups.reverse.each(&:clear)
  group.clear
  group.remove_from_project
  project.save
end

# @param [Xcodeproj::Project] project
def list_targets(project)
  project.native_targets.each do |target|
    puts target.name
  end
end

# @param [Xcodeproj::Project] project
# @param [String] file_path
def list_targets_for_file(project, file_path)
  get_targets_for_file(project, file_path).each do |target|
    puts target
  end
end

# @param [Xcodeproj::Project] project
# @param [String] dir_path
# @param [Boolean] go_up
def list_targets_for_group(project, dir_path, go_up = true)
  find_targets_for_group(project, dir_path, go_up).each do |target|
    puts target
  end
end

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
# @param [Xcodeproj::Project] project
# @param [String] dir_path
# @param [Boolean] go_up
# @return [Array<String>]
def find_targets_for_group(project, dir_path, go_up = true)
  dir_path = dir_path.chomp("/")
  group = find_group_by_absolute_dir_path(project, dir_path, false)
  project_dir = File.dirname(project.path.to_s)

  # Look for the first group that exists in the project.
  # We could be just creating a new path that doesn't exist yet.
  while group.nil? && dir_path != "" && dir_path != "/" && dir_path != project_dir
    dir_path = File.dirname(dir_path)
    group = find_group_by_absolute_dir_path(project, dir_path, false)
  end

  return [] if group.nil? || dir_path == project_dir || group.instance_of?(Xcodeproj::Project::Object::PBXProject)

  # First look for Swift files in the current group then in nested groups
  merged_children = group.files + group.recursive_children

  merged_children.each do |child|
    next unless child.instance_of?(Xcodeproj::Project::Object::PBXFileReference)

    # skip if the file is not a swift file
    extension = File.extname(child.real_path.to_s)
    next if extension != ".swift"

    # skip if the file doesn't belong to any target
    targets = get_targets_for_file(project, child.real_path.to_s)
    next if targets.empty?

    return targets
  end

  # Last chance, go up one level and try again
  find_targets_for_group(project, File.dirname(dir_path), false) if go_up
end

# @param [Xcodeproj::Project] project
# @param [String] file_path
def get_targets_for_file(project, file_path)
  result = []
  project.native_targets.each do |target|
    target.source_build_phase.files_references.each do |file|
      result << target.name if file.real_path.to_s == file_path
    end
  end

  result
end

# @param [Xcodeproj::Project] project
# @param [String] targets
# @param [String] file_path
# @param [Boolean] guess_target
# @param [Boolean] create_dirs
def add_file(project, targets, file_path, guess_target, create_dirs)
  if guess_target
    guessed_targets = find_targets_for_group(project, File.dirname(file_path))

    if guessed_targets.nil? || guessed_targets.empty?
      puts "Failure"
      list_targets(project)
      return
    end

    targets_joined = guessed_targets.join(",")
    add_group(project, File.dirname(file_path)) if create_dirs
    add_file_to_targets(project, targets_joined, file_path)

    puts "Success"
    guessed_targets.each { |target| puts target }
  else
    add_group(project, File.dirname(file_path)) if create_dirs
    add_file_to_targets(project, targets, file_path)
  end
end

# rubocop:disable Metrics/MethodLength, Style/GuardClause
# @param [Xcodeproj::Project] project
# @param [String] action
def handle_action(project, action)
  if action == "add_file"
    add_file(project, ARGV[2], ARGV[3], ARGV[4] == "true", ARGV[5] == "true")
    exit
  end

  if action == "delete_file"
    delete_file(project, ARGV[2])
    exit
  end

  if action == "rename_file"
    rename_file(project, ARGV[2], ARGV[3])
    exit
  end

  if action == "move_file"
    move_file(project, ARGV[2], ARGV[3])
    exit
  end

  if action == "add_group"
    add_group(project, ARGV[2])
    exit
  end

  if action == "delete_group"
    delete_group(project, ARGV[2])
    exit
  end

  if action == "rename_group"
    rename_group(project, ARGV[2], ARGV[3])
    exit
  end

  if action == "move_group"
    move_group(project, ARGV[2], ARGV[3])
    exit
  end

  if action == "update_file_targets"
    update_file_targets(project, ARGV[2], ARGV[3])
  end

  if action == "list_targets"
    list_targets(project)
    exit
  end

  if action == "list_targets_for_file"
    list_targets_for_file(project, ARGV[2])
    exit
  end

  if action == "list_targets_for_group"
    list_targets_for_group(project, ARGV[2])
    exit
  end
end
# rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity,
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Style/GuardClause

handle_action(project, action)
