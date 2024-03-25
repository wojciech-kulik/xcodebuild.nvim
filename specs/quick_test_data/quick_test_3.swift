class TableOfContentsSpec: QuickSpec {
    override class func spec() {
        describe("the 'Documentation' directory") {
            it("has everything you need to get started") {
                let sections = Directory("Documentation").sections
                expect(sections).to(contain("Organized Tests with Quick Examples and Example Groups"))
                expect(sections).to(contain("Installing Quick"))
            }

            context("if it doesn't have what you're looking for") {
                it("needs to be updated") {
                    let you = You(awesome: true)
                    expect { you.submittedAnIssue }.toEventually(beTruthy())
                }
            }
        }
    }
}
