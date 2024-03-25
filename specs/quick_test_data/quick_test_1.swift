import Nimble
import Quick

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

        fdescribe("Sample Focused Test") {
            fcontext("if test is focused") {
                fit("should run only this test") {
                    expect(1).to(equal(1))
                }

                fit("and this test") {
                    expect(1).to(equal(1))
                }
            }

            xcontext("if test is disabled") {
                xit("should not run this test") {
                    expect(1).to(equal(1))
                }

                xit("and this test") {
                    expect(1).to(equal(1))
                }
            }
        }

        context("just another tests") {
            it("should run this test") {
                expect(1).to(equal(1))
            }

            it("and this test") {
                expect(1).to(equal(1))
            }
        }
    }
}
