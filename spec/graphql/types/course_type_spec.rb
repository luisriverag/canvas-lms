# frozen_string_literal: true

#
# Copyright (C) 2017 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require_relative "../graphql_spec_helper"

describe Types::CourseType do
  let_once(:course) do
    course_with_student(active_all: true)
    @course
  end
  let(:course_type) { GraphQLTypeTester.new(course, current_user: @student) }

  let_once(:other_section) { course.course_sections.create! name: "other section" }
  let_once(:other_teacher) do
    course.enroll_teacher(user_factory, section: other_section, limit_privileges_to_course_section: true).user
  end

  it "works" do
    expect(course_type.resolve("_id")).to eq course.id.to_s
    expect(course_type.resolve("name")).to eq course.name
    expect(course_type.resolve("courseNickname")).to be_nil
  end

  it "works for root_outcome_group" do
    expect(course_type.resolve("rootOutcomeGroup { _id }")).to eq course.root_outcome_group.id.to_s
  end

  context "top-level permissions" do
    it "needs read permission" do
      course_with_student
      @course2, @student2 = @course, @student

      # node / legacy node
      expect(course_type.resolve("_id", current_user: @student2)).to be_nil

      # course
      expect(
        CanvasSchema.execute(<<~GQL, context: { current_user: @student2 }).dig("data", "course")
          query { course(id: "#{course.id}") { id } }
        GQL
      ).to be_nil
    end
  end

  context "sis fields" do
    let_once(:sis_course) do
      course.update!(sis_course_id: "SIScourseID")
      course
    end

    let(:admin) { account_admin_user_with_role_changes(role_changes: { read_sis: false }) }

    it "returns sis_id if you have read_sis permissions" do
      expect(
        CanvasSchema.execute(<<~GQL, context: { current_user: @teacher }).dig("data", "course", "sisId")
          query { course(id: "#{sis_course.id}") { sisId } }
        GQL
      ).to eq("SIScourseID")
    end

    it "returns sis_id if you have manage_sis permissions" do
      expect(
        CanvasSchema.execute(<<~GQL, context: { current_user: admin }).dig("data", "course", "sisId")
          query { course(id: "#{sis_course.id}") { sisId } }
        GQL
      ).to eq("SIScourseID")
    end

    it "doesn't return sis_id if you don't have read_sis or management_sis permissions" do
      expect(
        CanvasSchema.execute(<<~GQL, context: { current_user: @student }).dig("data", "course", "sisId")
          query { course(id: "#{sis_course.id}") { sisId } }
        GQL
      ).to be_nil
    end
  end

  describe "relevantGradingPeriodGroup" do
    let!(:grading_period_group) { Account.default.grading_period_groups.create!(title: "a test group") }

    it "returns the grading period group for the course" do
      enrollment_term = course.enrollment_term
      enrollment_term.update(grading_period_group_id: grading_period_group.id)
      expect(course.relevant_grading_period_group).to eq grading_period_group
      expect(course_type.resolve("relevantGradingPeriodGroup { _id }")).to eq grading_period_group.id.to_s
    end
  end

  context "connection types" do
    describe "assignmentsConnection" do
      let_once(:assignment) do
        course.assignments.create! name: "asdf", workflow_state: "unpublished"
      end

      context "user_id filter" do
        let_once(:other_student) do
          other_user = user_factory(active_all: true, active_state: "active")
          @course.enroll_student(other_user, enrollment_state: "active").user
        end

        # Create an observer in the course that observes the other_student
        let_once(:observer) do
          course_with_observer(course: @course, associated_user_id: other_student.id)
          @observer
        end

        # Create an assignment that is only visible to other_student
        before(:once) do
          # Set the assigment to active
          assignment.workflow_state = "active"
          assignment.save

          @overridden_assignment = course.assignments.create!(title: "asdf",
                                                              workflow_state: "published",
                                                              only_visible_to_overrides: true)

          override = assignment_override_model(assignment: @overridden_assignment)
          override.assignment_override_students.build(user: other_student)
          override.save!
        end

        it "filters assignments by userId correctly for students" do
          expect(
            course_type.resolve(<<~GQL, current_user: other_student)
              assignmentsConnection(filter: {userId: "#{other_student.id}"}) { edges { node { _id } } }
            GQL
          ).to eq [assignment.id.to_s, @overridden_assignment.id.to_s]

          # the other_student lacks permission to see @student's assignments
          expect(
            course_type.resolve(<<~GQL, current_user: other_student)
              assignmentsConnection(filter: {userId: "#{@student.id}"}) { edges { node { _id } } }
            GQL
          ).to eq []
        end

        it "filters assignments by userId correctly for observers" do
          expect(
            course_type.resolve(<<~GQL, current_user: observer)
              assignmentsConnection(filter: {userId: "#{other_student.id}"}) { edges { node { _id } } }
            GQL
          ).to eq [assignment.id.to_s, @overridden_assignment.id.to_s]

          # the observer doesn't observer @student, so it can not see their assignments
          expect(
            course_type.resolve(<<~GQL, current_user: observer)
              assignmentsConnection(filter: {userId: "#{@student.id}"}) { edges { node { _id } } }
            GQL
          ).to eq []
        end

        it "filters assignments by userId correctly for teachers" do
          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              assignmentsConnection(filter: {userId: "#{other_student.id}"}) { edges { node { _id } } }
            GQL
          ).to eq [assignment.id.to_s, @overridden_assignment.id.to_s]

          # A teacher has permission to see all assignments
          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              assignmentsConnection(filter: {userId: "#{@student.id}"}) { edges { node { _id } } }
            GQL
          ).to eq [assignment.id.to_s]
        end

        it "returns visible assignments to current user" do
          expect(course_type.resolve("assignmentsConnection { edges { node { _id } } }", current_user: @teacher).size).to eq 2
          expect(course_type.resolve("assignmentsConnection { edges { node { _id } } }", current_user: @student).size).to eq 1
          expect(course_type.resolve("assignmentsConnection { edges { node { _id } } }", current_user: other_student).size).to eq 2
        end
      end

      it "only returns visible assignments" do
        expect(course_type.resolve("assignmentsConnection { edges { node { _id } } }", current_user: @teacher).size).to eq 1
        expect(course_type.resolve("assignmentsConnection { edges { node { _id } } }", current_user: @student).size).to eq 0
      end

      context "grading periods" do
        before(:once) do
          gpg = GradingPeriodGroup.create! title: "asdf",
                                           root_account: course.root_account
          course.enrollment_term.update grading_period_group: gpg
          @term1 = gpg.grading_periods.create! title: "past grading period",
                                               start_date: 2.weeks.ago,
                                               end_date: 1.week.ago
          @term2 = gpg.grading_periods.create! title: "current grading period",
                                               start_date: 2.days.ago,
                                               end_date: 2.days.from_now
          @term1_assignment1 = course.assignments.create! name: "asdf",
                                                          due_at: 1.5.weeks.ago
          @term2_assignment1 = course.assignments.create! name: ";lkj",
                                                          due_at: Time.zone.today
        end

        it "only returns assignments for the current grading period" do
          expect(
            course_type.resolve("assignmentsConnection { edges { node { _id } } }", current_user: @student)
          ).to eq [@term2_assignment1.id.to_s]
        end

        it "returns no assignments when outside of a grading period" do
          @term2.destroy
          expect(
            course_type.resolve("assignmentsConnection { edges { node { _id } } }", current_user: @student)
          ).to eq []
        end

        it "returns assignments for the requested grading period" do
          expect(
            course_type.resolve(<<~GQL, current_user: @student)
              assignmentsConnection(filter: {gradingPeriodId: "#{@term1.id}"}) { edges { node { _id } } }
            GQL
          ).to eq [@term1_assignment1.id.to_s]
        end

        it "can still return assignments for all grading periods" do
          result = course_type.resolve(<<~GQL, current_user: @student)
            assignmentsConnection(filter: {gradingPeriodId: null}) { edges { node { _id } } }
          GQL
          expect(result.sort).to match course.assignments.published.map(&:to_param).sort
        end

        it "returns assignments in order by position" do
          ag = @course.assignment_groups.create! name: "Other Assignments", position: 1
          other_ag_assignment = @course.assignments.create! assignment_group: ag, name: "other ag"

          @term1_assignment1.assignment_group.update!(position: 2)
          @term2_assignment1.update!(position: 1)
          @term1_assignment1.update!(position: 2)

          expect(
            course_type.resolve(<<~GQL, current_user: @student)
              assignmentsConnection(filter: {gradingPeriodId: null}) { edges { node { _id } } }
            GQL
          ).to eq([
            other_ag_assignment,
            @term2_assignment1,
            @term1_assignment1,
          ].map { |a| a.id.to_s })
        end
      end

      context "grading standards" do
        it "returns grading standard title" do
          expect(
            course_type.resolve("gradingStandard { title }", current_user: @student)
          ).to eq "Default Grading Scheme"
        end

        it "returns grading standard id" do
          expect(
            course_type.resolve("gradingStandard { _id }", current_user: @student)
          ).to eq course.grading_standard_or_default.id
        end

        it "returns grading standard data" do
          expect(
            course_type.resolve("gradingStandard { data { letterGrade } }", current_user: @student)
          ).to eq ["A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F"]

          expect(
            course_type.resolve("gradingStandard { data { baseValue } }", current_user: @student)
          ).to eq [0.94, 0.9, 0.87, 0.84, 0.8, 0.77, 0.74, 0.7, 0.67, 0.64, 0.61, 0.0]
        end
      end

      context "apply assignment group weights" do
        it "returns false if not weighted" do
          expect(
            course_type.resolve("applyGroupWeights", current_user: @student)
          ).to be false
        end
      end

      context "searchTerm" do
        before do
          @discussion_1 = course.discussion_topics.create!(title: "asdf", message: "asdf")
          @discussion_2 = course.discussion_topics.create!(title: "asdf2", message: "asdf2")
          @discussion_3 = course.discussion_topics.create!(title: "asdf3", message: "asdf3")
        end

        it "returns discussions with general search term" do
          expect(
            course_type.resolve("discussionsConnection(filter: { searchTerm: \"asdf\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@discussion_1.id.to_s, @discussion_2.id.to_s, @discussion_3.id.to_s]
        end

        it "returns discussions with specific search term" do
          expect(
            course_type.resolve("discussionsConnection(filter: { searchTerm: \"asdf2\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@discussion_2.id.to_s]
        end
      end
    end

    context "discussionsConnection" do
      before do
        @discussion_1 = course.discussion_topics.create!(title: "asdf", message: "asdf")
        @discussion_2 = course.discussion_topics.create!(title: "asdf2", message: "asdf2")
        @discussion_3 = course.discussion_topics.create!(title: "asdf3", message: "asdf3")
      end

      it "returns discussions" do
        expect(
          course_type.resolve("discussionsConnection { edges { node { _id } } }", current_user: @teacher)
        ).to eq [@discussion_1.id.to_s, @discussion_2.id.to_s, @discussion_3.id.to_s]
      end

      context "searchTerm" do
        it "returns discussions with general search term" do
          expect(
            course_type.resolve("discussionsConnection(filter: { searchTerm: \"asdf\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@discussion_1.id.to_s, @discussion_2.id.to_s, @discussion_3.id.to_s]
        end

        it "returns discussions with specific search term" do
          expect(
            course_type.resolve("discussionsConnection(filter: { searchTerm: \"asdf2\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@discussion_2.id.to_s]
        end
      end

      context "as a student" do
        it "returns discussions" do
          expect(
            course_type.resolve("discussionsConnection { edges { node { _id } } }", current_user: @student)
          ).to eq [@discussion_1.id.to_s, @discussion_2.id.to_s, @discussion_3.id.to_s]
        end

        it "returns only discussions assigned to the student" do
          new_section = course.course_sections.create!(name: "new section")
          @discussion_1.assignment_overrides.create!(course_section: new_section)
          @discussion_1.update!(only_visible_to_overrides: true)
          expect(
            course_type.resolve("discussionsConnection { edges { node { _id } } }", current_user: @student)
          ).to eq [@discussion_2.id.to_s, @discussion_3.id.to_s]
        end
      end

      context "userId filter" do
        it "returns unauthorized code when user is not allowed to act as another user" do
          new_section = course.course_sections.create!(name: "new section")
          @discussion_1.assignment_overrides.create!(course_section: new_section)
          @discussion_1.update!(only_visible_to_overrides: true)
          expect_error = "You do not have permission to view this course."
          expect do
            course_type.resolve("discussionsConnection(filter: { userId: \"#{@teacher.id}\" }) { edges { node { _id } } }", current_user: @student)
          end.to raise_error(GraphQLTypeTester::Error, /#{Regexp.escape(expect_error)}/)
        end

        it "returns discussions assigned to the user_id when allowed to act as that user" do
          new_section = course.course_sections.create!(name: "new section")
          @discussion_1.assignment_overrides.create!(course_section: new_section)
          @discussion_1.update!(only_visible_to_overrides: true)
          expect(
            course_type.resolve("discussionsConnection(filter: { userId: \"#{@student.id}\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@discussion_2.id.to_s, @discussion_3.id.to_s]
        end
      end
    end

    context "pagesConnection" do
      before do
        @page_1 = course.wiki_pages.create!(title: "asdf", body: "asdf")
        @page_2 = course.wiki_pages.create!(title: "asdf2", body: "asdf2")
        @page_3 = course.wiki_pages.create!(title: "asdf3", body: "asdf3")
      end

      it "returns pages" do
        expect(
          course_type.resolve("pagesConnection { edges { node { _id } } }", current_user: @teacher)
        ).to eq [@page_1.id.to_s, @page_2.id.to_s, @page_3.id.to_s]
      end

      context "search" do
        it "returns pages with general search term" do
          expect(
            course_type.resolve("pagesConnection(filter: { searchTerm: \"asdf\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@page_1.id.to_s, @page_2.id.to_s, @page_3.id.to_s]
        end

        it "returns pages with specific search term" do
          expect(
            course_type.resolve("pagesConnection(filter: { searchTerm: \"asdf2\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@page_2.id.to_s]
        end
      end

      context "as a student" do
        it "returns pages" do
          expect(
            course_type.resolve("pagesConnection { edges { node { _id } } }", current_user: @student)
          ).to eq [@page_1.id.to_s, @page_2.id.to_s, @page_3.id.to_s]
        end

        it "returns only wiki pages assigned to the student" do
          new_section = course.course_sections.create!(name: "new section")
          @page_1.assignment_overrides.create!(course_section: new_section)
          @page_1.update!(only_visible_to_overrides: true)
          expect(
            course_type.resolve("pagesConnection { edges { node { _id } } }", current_user: @student)
          ).to eq [@page_2.id.to_s, @page_3.id.to_s]
        end
      end

      context "userId filter" do
        it "returns unauthorized code when user is not allowed to act as another user" do
          expect_error = "You do not have permission to view this course."
          expect do
            course_type.resolve("pagesConnection(filter: { userId: \"#{@teacher.id}\" }) { edges { node { _id } } }", current_user: @student)
          end.to raise_error(GraphQLTypeTester::Error, /#{Regexp.escape(expect_error)}/)
        end

        it "returns pages for the given user" do
          expect(
            course_type.resolve("pagesConnection(filter: { userId: \"#{@teacher.id}\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@page_1.id.to_s, @page_2.id.to_s, @page_3.id.to_s]
        end
      end
    end

    context "quizzesConnection" do
      before do
        @quiz_1 = course.quizzes.create!(title: "asdf", quiz_type: "assignment")
        @quiz_2 = course.quizzes.create!(title: "asdf2", quiz_type: "assignment")
        @quiz_3 = course.quizzes.create!(title: "asdf3", quiz_type: "assignment")
      end

      it "returns quizzes" do
        expect(
          course_type.resolve("quizzesConnection { edges { node { _id } } }", current_user: @teacher)
        ).to eq [@quiz_1.id.to_s, @quiz_2.id.to_s, @quiz_3.id.to_s]
      end

      context "searchTerm" do
        it "returns quizzes with general search term" do
          expect(
            course_type.resolve("quizzesConnection(filter: { searchTerm: \"asdf\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@quiz_1.id.to_s, @quiz_2.id.to_s, @quiz_3.id.to_s]
        end

        it "returns quizzes with specific search term" do
          expect(
            course_type.resolve("quizzesConnection(filter: { searchTerm: \"asdf2\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@quiz_2.id.to_s]
        end
      end

      context "as a student" do
        it "returns quizzes" do
          expect(
            course_type.resolve("quizzesConnection { edges { node { _id } } }", current_user: @student)
          ).to eq [@quiz_1.id.to_s, @quiz_2.id.to_s, @quiz_3.id.to_s]
        end

        it "returns only quizzes assigned to the student" do
          new_section = course.course_sections.create!(name: "new section")
          @quiz_1.assignment_overrides.create!(course_section: new_section)
          @quiz_1.update!(only_visible_to_overrides: true)
          expect(
            course_type.resolve("quizzesConnection { edges { node { _id } } }", current_user: @student)
          ).to eq [@quiz_2.id.to_s, @quiz_3.id.to_s]
        end
      end

      context "userId filter" do
        it "returns unauthorized code when user is not allowed to act as another user" do
          expect_error = "You do not have permission to view this course."
          expect do
            course_type.resolve("quizzesConnection(filter: { userId: \"#{@teacher.id}\" }) { edges { node { _id } } }", current_user: @student)
          end.to raise_error(GraphQLTypeTester::Error, /#{Regexp.escape(expect_error)}/)
        end

        it "returns quizzes for the given user" do
          expect(
            course_type.resolve("quizzesConnection(filter: { userId: \"#{@teacher.id}\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@quiz_1.id.to_s, @quiz_2.id.to_s, @quiz_3.id.to_s]
        end
      end
    end

    context "filesConnection" do
      before do
        @file_1 = course.attachments.create!(filename: "asdf", uploaded_data: default_uploaded_data)
        @file_2 = course.attachments.create!(filename: "asdf2", uploaded_data: default_uploaded_data)
        @file_3 = course.attachments.create!(filename: "asdf3", uploaded_data: default_uploaded_data)
      end

      it "returns files" do
        expect(
          course_type.resolve("filesConnection { edges { node { _id } } }", current_user: @teacher)
        ).to eq [@file_1.id.to_s, @file_2.id.to_s, @file_3.id.to_s]
      end

      context "search" do
        it "returns files with general search term" do
          expect(
            course_type.resolve("filesConnection(filter: { searchTerm: \"asdf\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@file_1.id.to_s, @file_2.id.to_s, @file_3.id.to_s]
        end

        it "returns files with specific search term" do
          expect(
            course_type.resolve("filesConnection(filter: { searchTerm: \"asdf2\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@file_2.id.to_s]
        end
      end

      context "userId filter" do
        it "returns unauthorized code when user is not allowed to act as another user" do
          expect_error = "You do not have permission to view this course."
          expect do
            course_type.resolve("filesConnection(filter: { userId: \"#{@teacher.id}\" }) { edges { node { _id } } }", current_user: @student)
          end.to raise_error(GraphQLTypeTester::Error, /#{Regexp.escape(expect_error)}/)
        end

        it "returns files for the given user" do
          expect(
            course_type.resolve("filesConnection(filter: { userId: \"#{@teacher.id}\" }) { edges { node { _id } } }", current_user: @teacher)
          ).to eq [@file_1.id.to_s, @file_2.id.to_s, @file_3.id.to_s]
        end
      end
    end
  end

  describe "customGradeStatusesConnection" do
    before do
      account_admin_user
      course.root_account.custom_grade_statuses.create!(
        color: "#BBB",
        created_by: @admin,
        name: "My Status"
      )
    end

    it "returns nil when the feature flag is disabled" do
      Account.site_admin.disable_feature!(:custom_gradebook_statuses)
      expect(
        course_type.resolve("customGradeStatusesConnection { edges { node { name } } }", current_user: @teacher)
      ).to be_nil
    end

    it "returns nil when the requesting user lacks needed permissions" do
      expect(
        course_type.resolve("customGradeStatusesConnection { edges { node { name } } }", current_user: @student)
      ).to be_nil
    end

    it "returns the custom grade statuses used by the course" do
      expect(
        course_type.resolve("customGradeStatusesConnection { edges { node { name } } }", current_user: @teacher)
      ).to match_array ["My Status"]
    end

    it "excludes custom statuses not used by the course" do
      new_account = Account.create!
      new_admin = account_admin_user(account: new_account)
      new_account.custom_grade_statuses.create!(color: "#AAA", created_by: new_admin, name: "Another Status")
      expect(
        course_type.resolve("customGradeStatusesConnection { edges { node { name } } }", current_user: @teacher)
      ).not_to include "Another Status"
    end
  end

  describe "gradeStatuses" do
    before do
      account_admin_user
    end

    it "always includes 'late', 'missing', 'none', and 'excused'" do
      expect(
        course_type.resolve("gradeStatuses", current_user: @teacher)
      ).to include("late", "missing", "none", "excused")
    end

    it "returns 'extended' only when the 'Extended Submission State' feature flag is enabled" do
      expect do
        course.root_account.disable_feature!(:extended_submission_state)
      end.to change {
        course_type.resolve("gradeStatuses", current_user: @teacher).include?("extended")
      }.from(true).to(false)
    end
  end

  describe "outcomeProficiency" do
    it "resolves to the account proficiency" do
      outcome_proficiency_model(course.account)
      expect(
        course_type.resolve("outcomeProficiency { _id }", current_user: @teacher)
      ).to eq course.account.outcome_proficiency.id.to_s
    end
  end

  describe "outcomeCalculationMethod" do
    it "resolves to the account calculation method" do
      outcome_calculation_method_model(course.account)
      expect(
        course_type.resolve("outcomeCalculationMethod { _id }", current_user: @teacher)
      ).to eq course.account.outcome_calculation_method.id.to_s
    end
  end

  context "outcomeAlignmentStats" do
    before do
      account_admin_user
      outcome_alignment_stats_model
      course_with_student(course: @course)
      @course.account.enable_feature!(:improved_outcomes_management)
    end

    context "for users with Admin role" do
      it "resolves outcome alignment stats" do
        course_type = GraphQLTypeTester.new(@course, { current_user: @admin })
        expect(course_type.resolve("outcomeAlignmentStats { totalOutcomes }")).to eq 2
        expect(course_type.resolve("outcomeAlignmentStats { alignedOutcomes }")).to eq 1
      end
    end

    context "for users with Teacher role" do
      it "resolves outcome alignment stats" do
        course_type = GraphQLTypeTester.new(@course, { current_user: @teacher })
        expect(course_type.resolve("outcomeAlignmentStats { totalOutcomes }")).to eq 2
        expect(course_type.resolve("outcomeAlignmentStats { alignedOutcomes }")).to eq 1
      end
    end

    context "for users with Student role" do
      it "does not resolve outcome alignment stats" do
        course_type = GraphQLTypeTester.new(@course, { current_user: @student })
        expect(course_type.resolve("outcomeAlignmentStats { totalOutcomes }")).to be_nil
      end
    end
  end

  describe "sectionsConnection" do
    it "only includes active sections" do
      section1 = course.course_sections.create!(name: "Delete Me")
      expect(
        course_type.resolve("sectionsConnection { edges { node { _id } } }")
      ).to match_array course.course_sections.map(&:to_param)

      section1.destroy
      expect(
        course_type.resolve("sectionsConnection { edges { node { _id } } }")
      ).to match_array course.course_sections.active.map(&:to_param)
    end

    describe "assignmentId filter" do
      before do
        other_section_student = course_with_student(active_all: true, course:, section: other_section).user
        @assignment = course.assignments.create!(only_visible_to_overrides: true)
        create_adhoc_override_for_assignment(@assignment, other_section_student)
      end

      let(:query) { "sectionsConnection(filter: { assignmentId: #{@assignment.id} }) { edges { node { _id } } }" }

      it "returns course sections associated with the assignment's assigned students" do
        expect(course_type.resolve(query)).to match_array [other_section.to_param]
      end

      it "raises an error if the provided assignment is soft-deleted" do
        @assignment.destroy
        expect { course_type.resolve(query) }.to raise_error(/assignment not found/)
      end
    end
  end

  describe "modulesConnection" do
    it "returns course modules" do
      modulea = course.context_modules.create! name: "module a"
      course.context_modules.create! name: "module b"
      expect(
        course_type.resolve("modulesConnection { edges {node { _id } } }")
      ).to match_array course.context_modules.map(&:to_param)

      modulea.destroy
      expect(
        course_type.resolve("modulesConnection { edges {node { _id } } }")
      ).to match_array course.modules_visible_to(@student).map(&:to_param)
    end
  end

  context "submissionsConnection" do
    before(:once) do
      a1 = course.assignments.create! name: "one", points_possible: 10
      a2 = course.assignments.create! name: "two", points_possible: 10

      @student1 = @student
      student_in_course(active_all: true)
      @student2 = @student

      @student1a1_submission, _ = a1.grade_student(@student1, grade: 1, grader: @teacher)
      @student1a2_submission, _ = a2.grade_student(@student1, grade: 9, grader: @teacher)
      @student2a1_submission, _ = a1.grade_student(@student2, grade: 5, grader: @teacher)

      @student1a1_submission.update_attribute :graded_at, 4.days.ago
      @student1a2_submission.update_attribute :graded_at, 2.days.ago
      @student2a1_submission.update_attribute :graded_at, 3.days.ago
    end

    it "returns submissions for specified students" do
      expect(
        course_type.resolve(<<~GQL, current_user: @teacher)
          submissionsConnection(
            studentIds: ["#{@student1.id}", "#{@student2.id}"],
            orderBy: [{field: _id, direction: ascending}]
          ) { edges { node { _id } } }
        GQL
      ).to eq [
        @student1a1_submission.id.to_s,
        @student1a2_submission.id.to_s,
        @student2a1_submission.id.to_s,
      ].sort
    end

    it "doesn't let students see other student's submissions" do
      expect(
        course_type.resolve(<<~GQL, current_user: @student2)
          submissionsConnection(
            studentIds: ["#{@student1.id}", "#{@student2.id}"],
          ) { edges { node { _id } } }
        GQL
      ).to eq [@student2a1_submission.id.to_s]

      expect(
        course_type.resolve(<<~GQL, current_user: @student2)
          submissionsConnection { nodes { _id } }
        GQL
      ).to eq [@student2a1_submission.id.to_s]
    end

    context "sorting criteria" do
      it "takes sorting criteria" do
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            submissionsConnection(
              studentIds: ["#{@student1.id}", "#{@student2.id}"],
              orderBy: [{field: gradedAt, direction: descending}]
            ) { edges { node { _id } } }
          GQL
        ).to eq [
          @student1a2_submission.id.to_s,
          @student2a1_submission.id.to_s,
          @student1a1_submission.id.to_s,
        ]
      end

      it "sorts null last" do
        @student2a1_submission.update_attribute :graded_at, nil

        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            submissionsConnection(
              studentIds: ["#{@student1.id}", "#{@student2.id}"],
              orderBy: [{field: gradedAt, direction: descending}]
            ) { edges { node { _id } } }
          GQL
        ).to eq [
          @student1a2_submission.id.to_s,
          @student1a1_submission.id.to_s,
          @student2a1_submission.id.to_s,
        ]
      end
    end

    context "filtering" do
      it "allows filtering submissions by their state" do
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            submissionsConnection(
              studentIds: ["#{@student1.id}"],
              filter: {states: [unsubmitted]}
            ) { edges { node { _id } } }
          GQL
        ).to eq []
      end

      it "submitted_since" do
        @student1a1_submission.update_attribute(:submitted_at, 1.month.ago)
        @student1a2_submission.update_attribute(:submitted_at, 1.day.ago)

        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            submissionsConnection(
              filter: { submittedSince: "#{5.days.ago.iso8601}" }
            ) { nodes { _id } }
          GQL
        ).to eq [@student1a2_submission.id.to_s]
      end

      it "graded_since" do
        @student2a1_submission.update_attribute(:graded_at, 1.week.from_now)
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            submissionsConnection(
              filter: { gradedSince: "#{1.day.from_now.iso8601}" }
            ) { nodes { _id } }
          GQL
        ).to eq [@student2a1_submission.id.to_s]
      end

      it "updated_since" do
        @student2a1_submission.update_attribute(:updated_at, 1.week.from_now)
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            submissionsConnection(
              filter: { updatedSince: "#{1.day.from_now.iso8601}" }
            ) { nodes { _id } }
          GQL
        ).to eq [@student2a1_submission.id.to_s]
      end

      describe "due_between" do
        it "accepts a full range" do
          @student2a1_submission.assignment.update(due_at: 3.days.ago)

          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              submissionsConnection(
                filter: {
                  dueBetween: {
                    start: "#{1.week.ago.iso8601}",
                    end: "#{1.day.ago.iso8601}"
                  }
                }
              ) { nodes { _id } }
            GQL
          ).to include @student2a1_submission.id.to_s
        end

        it "does not include submissions out of the range" do
          @student2a1_submission.assignment.update(due_at: 8.days.ago)

          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              submissionsConnection(
                filter: {
                  dueBetween: {
                    start: "#{1.week.ago.iso8601}",
                    end: "#{1.day.ago.iso8601}"
                  }
                }
              ) { nodes { _id } }
            GQL
          ).to_not include @student2a1_submission.id.to_s
        end

        it "accepts a start-open range" do
          @student2a1_submission.assignment.update(due_at: 3.days.ago)

          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              submissionsConnection(
                filter: {
                  dueBetween: {
                    end: "#{1.day.ago.iso8601}"
                  }
                }
              ) { nodes { _id } }
            GQL
          ).to include @student2a1_submission.id.to_s
        end

        it "accepts a end-open range" do
          @student2a1_submission.assignment.update(due_at: 3.days.ago)

          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              submissionsConnection(
                filter: {
                  dueBetween: {
                    start: "#{1.week.ago.iso8601}",
                  }
                }
              ) { nodes { _id } }
            GQL
          ).to include @student2a1_submission.id.to_s
        end
      end
    end
  end

  context "users and enrollments" do
    before(:once) do
      @student1 = @student
      @student2 = student_in_course(active_all: true).user
      @inactive_user = student_in_course.tap(&:invite).user
      @concluded_user = student_in_course.tap(&:complete).user
    end

    describe "usersConnection" do
      it "returns all visible users" do
        expect(
          course_type.resolve(
            "usersConnection { edges { node { _id } } }",
            current_user: @teacher
          )
        ).to eq [@teacher, @student1, other_teacher, @student2, @inactive_user].map(&:to_param)
      end

      it "returns all visible users in alphabetical order by the sortable_name" do
        expected_users = [@teacher, @student1, other_teacher, @student2, @inactive_user]
                         .sort_by(&:sortable_name)
                         .map(&:to_param)

        actual_user_response = course_type.resolve(
          "usersConnection { edges { node { _id } } }",
          current_user: @teacher
        )

        expect(actual_user_response).to eq(expected_users)
      end

      it "returns only the specified users" do
        # deprecated method
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            usersConnection(userIds: ["#{@student1.id}"]) { edges { node { _id } } }
          GQL
        ).to eq [@student1.to_param]

        # current method
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            usersConnection(filter: {userIds: ["#{@student1.id}"]}) { edges { node { _id } } }
          GQL
        ).to eq [@student1.to_param]
      end

      it "doesn't return users that aren't visible to you" do
        expect(
          course_type.resolve(
            "usersConnection { edges { node { _id } } }",
            current_user: other_teacher
          )
        ).to eq [other_teacher.id.to_s]
      end

      it "allows filtering by enrollment state" do
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            usersConnection(
              filter: {enrollmentStates: [active completed]}
            ) { edges { node { _id } } }
          GQL
        ).to match_array [@teacher, @student1, @student2, @concluded_user].map(&:to_param)
      end

      it "allows filtering by enrollment type" do
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            usersConnection(
              filter: {enrollmentTypes: [TeacherEnrollment]}
            ) { edges { node { _id } } }
          GQL
        ).to match_array [@teacher, other_teacher].map(&:to_param)
        expect(
          course_type.resolve(<<~GQL, current_user: @teacher)
            usersConnection(
              filter: {enrollmentTypes: [StudentEnrollment]}
            ) { edges { node { _id } } }
          GQL
        ).to match_array [@student1, @student2, @inactive_user].map(&:to_param)
      end

      context "loginId" do
        def pseud_params(unique_id, account = Account.default)
          {
            account:,
            unique_id:,
          }
        end

        before do
          users = [@teacher, @student1, other_teacher, @student2, @inactive_user]
          @pseudonyms = users.map { |user| user.pseudonyms.create!(pseud_params("#{user.id}@example.com")).unique_id }
        end

        it "returns loginId for all users when requested by a teacher" do
          expect(
            course_type.resolve(
              "usersConnection { edges { node { loginId } } }",
              current_user: @teacher
            )
          ).to eq @pseudonyms
        end

        it "does not return loginId for any users when requested by a student" do
          expect(
            course_type.resolve(
              "usersConnection { edges { node { loginId } } }",
              current_user: @student1
            )
          ).to eq [nil, nil, nil, nil, nil]
        end
      end

      context "search term" do
        before(:once) do
          @student_with_name = student_in_course(active_all: true).user
          @student_with_name.update!(name: "John Doe")
          @student_with_email = student_in_course(active_all: true).user
          @student_with_email.update!(name: "Jane Smith")
          @student_with_email.email = "jsmith@example.com"
          @student_with_email.save!
          @student_with_sis = student_in_course(active_all: true).user
          @student_with_sis.pseudonyms.create!(
            account: Account.default,
            sis_user_id: "sis_123",
            unique_id: "uid_123"
          )
          @student_with_login = student_in_course(active_all: true).user
          @student_with_login.pseudonyms.create!(
            account: Account.default,
            unique_id: "uid_456"
          )
        end

        it "filters users by search term matching name" do
          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              usersConnection(filter: {searchTerm: "john"}) { edges { node { _id } } }
            GQL
          ).to eq [@student_with_name.to_param]
        end

        it "filters users by search term matching email when user has permissions" do
          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              usersConnection(filter: {searchTerm: "jsmith@example"}) { edges { node { _id } } }
            GQL
          ).to eq [@student_with_email.to_param]
        end

        it "does not match email when user lacks permissions" do
          expect(
            course_type.resolve(<<~GQL, current_user: @student1)
              usersConnection(filter: {searchTerm: "jsmith@example"}) { edges { node { _id } } }
            GQL
          ).to be_empty
        end

        it "filters users by search term matching SIS ID when user has permissions" do
          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              usersConnection(filter: {searchTerm: "sis_123"}) { edges { node { _id } } }
            GQL
          ).to eq [@student_with_sis.to_param]
        end

        it "does not match SIS ID when user lacks permissions" do
          expect(
            course_type.resolve(<<~GQL, current_user: @student1)
              usersConnection(filter: {searchTerm: "sis_123"}) { edges { node { _id } } }
            GQL
          ).to be_empty
        end

        it "filters users by search term matching login ID when user has permissions" do
          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              usersConnection(filter: {searchTerm: "uid_456"}) { edges { node { _id } } }
            GQL
          ).to eq [@student_with_login.to_param]
        end

        it "does not match login ID when user lacks permissions" do
          expect(
            course_type.resolve(<<~GQL, current_user: @student1)
              usersConnection(filter: {searchTerm: "uid_456"}) { edges { node { _id } } }
            GQL
          ).to be_empty
        end

        it "returns empty when search term does not match users" do
          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              usersConnection(filter: {searchTerm: "nonexistent"}) { edges { node { _id } } }
            GQL
          ).to be_empty
        end

        it "throws error if search term is too short" do
          result = CanvasSchema.execute(<<~GQL, context: { current_user: @teacher })
            query {
              course(id: "#{course.id}") {
                usersConnection(filter: {searchTerm: "a"}) {
                  edges { node { _id } }
                }
              }
            }
          GQL

          expect(result["errors"]).to be_present
          expect(result["errors"][0]["message"]).to match(/at least 2 characters/)
        end

        it "ignores search term if empty string" do
          expect(
            course_type.resolve(<<~GQL, current_user: @teacher)
              usersConnection(filter: {searchTerm: ""}) { edges { node { _id } } }
            GQL
          ).to match_array([
            @teacher,
            @student1,
            other_teacher,
            @student2,
            @inactive_user,
            @student_with_name,
            @student_with_email,
            @student_with_sis,
            @student_with_login
          ].map(&:to_param))
        end
      end
    end

    describe "enrollmentsConnection" do
      it "works" do
        expect(
          course_type.resolve(
            "enrollmentsConnection { nodes { _id } }",
            current_user: @teacher
          )
        ).to match_array @course.all_enrollments.map(&:to_param)
      end

      it "doesn't return users not visible to current_user" do
        expect(
          course_type.resolve(
            "enrollmentsConnection { nodes { _id } }",
            current_user: other_teacher
          )
        ).to match_array [
          @teacher.enrollments.first.id.to_s,
          other_teacher.enrollments.first.id.to_s,
        ]
      end

      it "returns nil for each user's initial lastActivityAt" do
        expect(
          course_type.resolve(
            "enrollmentsConnection { nodes { lastActivityAt } }",
            current_user: @teacher
          )
        ).to eq [nil, nil, nil, nil, nil, nil]
      end

      it "returns a datetime for each user enrollment once its last activity has been updated" do
        last_activity = "2022-08-01T00:00:00Z"
        course.enrollments.each do |enrollment|
          enrollment.last_activity_at = last_activity
          enrollment.save
          last_activity = (Date.parse(last_activity) + 1.day).to_s
        end

        expect(
          course_type.resolve(
            "enrollmentsConnection { nodes { lastActivityAt } }",
            current_user: @teacher
          ).sort
        ).to eq [
          "2022-08-01T00:00:00Z",
          "2022-08-02T00:00:00Z",
          "2022-08-03T00:00:00Z",
          "2022-08-04T00:00:00Z",
          "2022-08-05T00:00:00Z",
          "2022-08-06T00:00:00Z"
        ]
      end

      it "returns nil for other users's initial lastActivityAt if current user does not have appropriate permissions" do
        last_activity = "2022-08-01T00:00:00Z"
        course.enrollments.each do |enrollment|
          enrollment.last_activity_at = last_activity
          enrollment.save
          last_activity = (Date.parse(last_activity) + 1.day).to_s
        end

        student_last_activity = course_type.resolve(
          "enrollmentsConnection { nodes { lastActivityAt } }",
          current_user: @student1
        ).compact

        expect(student_last_activity).to have(1).items
        expect(Time.iso8601(student_last_activity.first)).to be_within(1.second)
          .of(@student1.enrollments.first.last_activity_at)
      end

      it "returns zero for each user's initial totalActivityTime" do
        expect(
          course_type.resolve(
            "enrollmentsConnection { nodes { totalActivityTime } }",
            current_user: @teacher
          )
        ).to eq [0, 0, 0, 0, 0, 0]
      end

      it "returns nil for other users's initial totalActivityTime if current user does not have appropriate permissions" do
        expected_total_activity_time = [nil, 0, nil, nil, nil, nil]

        result_total_activity_time = course_type.resolve(
          "enrollmentsConnection { nodes { totalActivityTime } }",
          current_user: @student1
        )

        expect(result_total_activity_time).to match_array(expected_total_activity_time)
      end

      it "returns the sisRole of each user" do
        expected_sis_roles = %w[teacher student teacher student student student]

        result_sis_roles = course_type.resolve(
          "enrollmentsConnection { nodes { sisRole } }",
          current_user: @teacher
        )

        expect(result_sis_roles).to match_array(expected_sis_roles)
      end

      it "returns an htmlUrl for each enrollment" do
        expected_urls = [@teacher, @student1, other_teacher, @student2, @inactive_user, @concluded_user]
                        .map { |user| "http://test.host/courses/#{@course.id}/users/#{user.id}" }

        result_urls = course_type.resolve(
          "enrollmentsConnection { nodes { htmlUrl } }",
          current_user: @teacher,
          request: ActionDispatch::TestRequest.create
        )

        expect(result_urls).to match_array(expected_urls)
      end

      it "returns canBeRemoved boolean value for each enrollment" do
        expected_can_be_removed = [false, true, true, true, true, true]

        result_can_be_removed = course_type.resolve(
          "enrollmentsConnection { nodes { canBeRemoved } }",
          current_user: @teacher
        )

        expect(result_can_be_removed).to match_array(expected_can_be_removed)
      end

      describe "filtering" do
        it "returns only enrollments of the specified types if included" do
          ta_enrollment = course.enroll_ta(User.create!, enrollment_state: :active)

          expect(
            course_type.resolve(
              "enrollmentsConnection(filter: {types: [TeacherEnrollment, TaEnrollment]}) { nodes { _id } }",
              current_user: @teacher
            )
          ).to match_array([
                             @teacher.enrollments.first.id.to_s,
                             other_teacher.enrollments.first.id.to_s,
                             ta_enrollment.id.to_s
                           ])
        end

        it "returns only enrollments with the specified associated_user_ids if included" do
          observer = User.create!
          observer_enrollment = observer_in_course(course: @course, user: observer)
          observer_enrollment.update!(associated_user: @student1)

          other_observer_enrollment = observer_in_course(course: @course, user: observer)
          other_observer_enrollment.update!(associated_user: @student2)

          expect(
            course_type.resolve(
              "enrollmentsConnection(filter: {associatedUserIds: [#{@student1.id}]}) { nodes { _id } }",
              current_user: @teacher
            )
          ).to eq [observer_enrollment.id.to_s]
        end

        it "returns only enrollments with the specified states if included" do
          inactive_student = course.enroll_user(User.create!, "StudentEnrollment", enrollment_state: "inactive").user
          deleted_student = course.enroll_user(User.create!, "StudentEnrollment", enrollment_state: "deleted").user
          rejected_student = course.enroll_user(User.create!, "StudentEnrollment", enrollment_state: "rejected").user
          expect(
            course_type.resolve(
              "enrollmentsConnection(filter: {states: [inactive, deleted, rejected]}) { nodes { _id } }",
              current_user: @teacher
            )
          ).to eq [inactive_student.enrollments.first.id.to_s, deleted_student.enrollments.first.id.to_s, rejected_student.enrollments.first.id.to_s]
        end
      end
    end
  end

  describe "AssignmentGroupConnection" do
    it "returns assignment groups" do
      ag = course.assignment_groups.create!(name: "a group")
      ag2 = course.assignment_groups.create!(name: "another group")
      ag2.destroy
      expect(
        course_type.resolve("assignmentGroupsConnection { edges { node { _id } } }")
      ).to eq [ag.to_param]
    end
  end

  describe "GroupsConnection" do
    before(:once) do
      @cg = course.groups.create! name: "A Group"
      ncc = course.group_categories.create! name: "Non-Collaborative Category", non_collaborative: true
      @ncg = course.groups.create! name: "Non-Collaborative Group", non_collaborative: true, group_category: ncc
    end

    it "returns student groups" do
      expect(
        course_type.resolve("groupsConnection { edges { node { _id } } }")
      ).to eq [@cg.to_param]
    end

    context "differentiation_tags" do
      before :once do
        Account.site_admin.enable_feature!(:differentiation_tags)
        @teacher = course.enroll_teacher(user_factory, section: other_section, limit_privileges_to_course_section: false).user
      end

      it "returns combined student groups and non-collaborative groups for users with sufficient permission" do
        RoleOverride::GRANULAR_MANAGE_TAGS_PERMISSIONS.each do |permission|
          course.account.role_overrides.create!(
            permission:,
            role: teacher_role,
            enabled: true
          )
        end

        tester = GraphQLTypeTester.new(course, current_user: @teacher)
        res = tester.resolve("groupsConnection(includeNonCollaborative: true) { edges { node { _id } } }")
        expect(res).to match_array([@cg.id.to_param, @ncg.id.to_param])
      end

      it "returns only collaborative groups if includeNonCollaborative is not provided" do
        RoleOverride::GRANULAR_MANAGE_TAGS_PERMISSIONS.each do |permission|
          course.account.role_overrides.create!(
            permission:,
            role: teacher_role,
            enabled: true
          )
        end

        tester = GraphQLTypeTester.new(course, current_user: @teacher)
        res = tester.resolve("groupsConnection { edges { node { _id } } }")
        expect(res).to match_array([@cg.id.to_param])
      end

      it "returns only collaborative groups if the user does not have sufficient permissions" do
        # course_type is student, keep in mind, the feature flag for :differentiation_tags is enabled
        expect(
          course_type.resolve("groupsConnection(includeNonCollaborative: true) { edges { node { _id } } }")
        ).to eq [@cg.to_param]
      end
    end
  end

  describe "groupSetsConnection" do
    before(:once) do
      @teacher_role = Role.get_built_in_role("TeacherEnrollment", root_account_id: Account.default.id)
      @project_groups = course.group_categories.create! name: "Project Groups"
      @student_groups = GroupCategory.student_organized_for(course)
      @non_collaborative_groups = course.group_categories.create! name: "NC Groups", non_collaborative: true
    end

    it "returns project group sets (not student_organized, not non_collaborative) when not asked for" do
      expect(
        course_type.resolve("groupSetsConnection { edges { node { _id } } }",
                            current_user: @teacher)
      ).to eq [@project_groups.id.to_s]
    end

    it "includes non_collaborative group sets when asked for by someone with permissions" do
      @course.account.enable_feature!(:differentiation_tags)
      RoleOverride::GRANULAR_MANAGE_TAGS_PERMISSIONS.each do |permission|
        @course.account.role_overrides.create!(
          permission:,
          role: @teacher_role,
          enabled: true
        )
      end

      expect(
        course_type.resolve("groupSetsConnection(includeNonCollaborative: true) { edges { node { _id } } }",
                            current_user: @teacher)
      ).to match_array [@project_groups.id.to_s, @non_collaborative_groups.id.to_s]
    end

    it "does not include non_collaborative group sets when asked for by someone without permissions" do
      @course.account.enable_feature!(:differentiation_tags)
      RoleOverride::GRANULAR_MANAGE_TAGS_PERMISSIONS.each do |permission|
        @course.account.role_overrides.create!(
          permission:,
          role: @teacher_role,
          enabled: false
        )
      end
      expect(
        course_type.resolve("groupSetsConnection { edges { node { _id } } }",
                            current_user: @teacher)
      ).to eq [@project_groups.id.to_s]
    end
  end

  describe "groupSets" do
    before(:once) do
      @teacher_role = Role.get_built_in_role("TeacherEnrollment", root_account_id: Account.default.id)
      @project_groups = course.group_categories.create! name: "Project Groups"
      @student_groups = GroupCategory.student_organized_for(course)
      @non_collaborative_groups = course.group_categories.create! name: "NC Groups", non_collaborative: true
    end

    it "returns project group sets (not student_organized, not non_collaborative) when not asked for" do
      expect(
        course_type.resolve("groupSets { _id}",
                            current_user: @teacher)
      ).to eq [@project_groups.id.to_s]
    end

    it "includes non_collaborative group sets when asked for by someone with permissions" do
      @course.account.enable_feature!(:differentiation_tags)
      RoleOverride::GRANULAR_MANAGE_TAGS_PERMISSIONS.each do |permission|
        @course.account.role_overrides.create!(
          permission:,
          role: @teacher_role,
          enabled: true
        )
      end

      expect(
        course_type.resolve("groupSets(includeNonCollaborative: true) { _id }",
                            current_user: @teacher)
      ).to match_array [@project_groups.id.to_s, @non_collaborative_groups.id.to_s]
    end

    it "excludes non_collaborative group sets when asked for by someone without permissions" do
      @course.account.enable_feature!(:differentiation_tags)
      RoleOverride::GRANULAR_MANAGE_TAGS_PERMISSIONS.each do |permission|
        @course.account.role_overrides.create!(
          permission:,
          role: @teacher_role,
          enabled: false
        )
      end

      expect(
        course_type.resolve("groupSets(includeNonCollaborative: true) { _id }",
                            current_user: @teacher)
      ).to match_array [@project_groups.id.to_s]
    end
  end

  describe "term" do
    before(:once) do
      course.enrollment_term.update(start_at: 1.month.ago)
    end

    it "works" do
      expect(
        course_type.resolve("term { _id }")
      ).to eq course.enrollment_term.id.to_s
      expect(
        course_type.resolve("term { name }")
      ).to eq course.enrollment_term.name
      expect(
        course_type.resolve("term { startAt }")
      ).to eq course.enrollment_term.start_at.iso8601
    end
  end

  describe "PostPolicy" do
    let(:assignment) { course.assignments.create! }
    let(:course) { Course.create!(workflow_state: "available") }
    let(:student) { course.enroll_user(User.create!, "StudentEnrollment", enrollment_state: "active").user }
    let(:teacher) { course.enroll_user(User.create!, "TeacherEnrollment", enrollment_state: "active").user }

    context "when user has manage_grades permission" do
      let(:context) { { current_user: teacher } }

      it "returns the PostPolicy for the course" do
        resolver = GraphQLTypeTester.new(course, context)
        expect(resolver.resolve("postPolicy { _id }").to_i).to eql course.default_post_policy.id
      end

      it "returns null if there is no course-specific PostPolicy" do
        course.default_post_policy.destroy
        resolver = GraphQLTypeTester.new(course, context)
        expect(resolver.resolve("postPolicy { _id }")).to be_nil
      end
    end

    context "when user does not have manage_grades permission" do
      let(:context) { { current_user: student } }

      it "returns null in place of the PostPolicy" do
        course.default_post_policy.update!(post_manually: true)
        resolver = GraphQLTypeTester.new(course, context)
        expect(resolver.resolve("postPolicy { _id }")).to be_nil
      end
    end
  end

  describe "AssignmentPostPoliciesConnection" do
    let(:course) { Course.create!(workflow_state: "available") }
    let(:student) { course.enroll_user(User.create!, "StudentEnrollment", enrollment_state: "active").user }
    let(:teacher) { course.enroll_user(User.create!, "TeacherEnrollment", enrollment_state: "active").user }

    context "when user has manage_grades permission" do
      let(:context) { { current_user: teacher } }

      it "returns only the assignment PostPolicies for the course" do
        assignment1 = course.assignments.create!
        assignment2 = course.assignments.create!

        resolver = GraphQLTypeTester.new(course, context)
        ids = resolver.resolve("assignmentPostPolicies { nodes { _id } }").map(&:to_i)
        expect(ids).to contain_exactly(assignment1.post_policy.id, assignment2.post_policy.id)
      end

      it "returns null if there are no assignment PostPolicies" do
        course.post_policies.where.not(assignment: nil).destroy_all
        resolver = GraphQLTypeTester.new(course, context)
        expect(resolver.resolve("assignmentPostPolicies { nodes { _id } }")).to be_empty
      end
    end

    context "when user does not have manage_grades permission" do
      let(:context) { { current_user: student } }

      it "returns null in place of the PostPolicy" do
        resolver = GraphQLTypeTester.new(course, context)
        expect(resolver.resolve("assignmentPostPolicies { nodes { _id } }")).to be_nil
      end
    end
  end

  describe "Account" do
    it "works" do
      expect(course_type.resolve("account { _id }")).to eq course.account.id.to_s
    end
  end

  describe "imageUrl" do
    it "returns a url from an uploaded image" do
      course.image_id = attachment_model(context: @course).id
      course.save!
      expect(course_type.resolve("imageUrl")).to_not be_nil
    end

    it "returns a url from id when url is blank" do
      course.image_url = ""
      course.image_id = attachment_model(context: @course).id
      course.save!
      expect(course_type.resolve("imageUrl")).to_not be_nil
      expect(course_type.resolve("imageUrl")).to_not eq ""
    end

    it "returns a url from settings" do
      course.image_url = "http://some.cool/gif.gif"
      course.save!
      expect(course_type.resolve("imageUrl")).to eq "http://some.cool/gif.gif"
    end
  end

  describe "AssetString" do
    it "returns the asset string" do
      result = course_type.resolve("assetString")
      expect(result).to eq @course.asset_string
    end
  end

  describe "AllowFinalGradeOverride" do
    it "returns the final grade override policy" do
      result = course_type.resolve("allowFinalGradeOverride")
      expect(result).to eq @course.allow_final_grade_override
    end
  end

  describe "RubricsConnection" do
    before(:once) do
      rubric_for_course
      rubric_association_model(context: course, rubric: @rubric, association_object: course, purpose: "bookmark")
    end

    it "returns rubrics" do
      expect(
        course_type.resolve("rubricsConnection { edges { node { _id } } }")
      ).to eq [course.rubrics.first.to_param]

      expect(
        course_type.resolve("rubricsConnection { edges { node { criteriaCount } } }")
      ).to eq [1]

      expect(
        course_type.resolve("rubricsConnection { edges { node { workflowState } } }")
      ).to eq ["active"]
    end
  end

  describe "ActivityStream" do
    it "return activity stream summaries" do
      cur_course = Course.create!
      new_teacher = User.create!
      cur_course.enroll_teacher(new_teacher).accept
      cur_course.announcements.create! title: "hear ye!", message: "wat"
      cur_course.discussion_topics.create!
      cur_resolver = GraphQLTypeTester.new(cur_course, current_user: new_teacher)
      expect(cur_resolver.resolve("activityStream { summary { type } } ")).to match_array ["DiscussionTopic", "Announcement"]
      expect(cur_resolver.resolve("activityStream { summary { count } } ")).to match_array [1, 1]
      expect(cur_resolver.resolve("activityStream { summary { unreadCount } } ")).to match_array [1, 1]
      expect(cur_resolver.resolve("activityStream { summary { notificationCategory } } ")).to match_array [nil, nil]
    end
  end

  describe "moderators" do
    def execute_query(pagination_options: {}, user: @teacher)
      options_string = pagination_options.empty? ? "" : "(#{pagination_options.map { |key, value| "#{key}: #{value.inspect}" }.join(", ")})"
      CanvasSchema.execute(<<~GQL, context: { current_user: user }).dig("data", "course")
        query {
          course(id: #{course.id}) {
            availableModerators#{options_string} {
              edges {
                node {
                  _id
                  name
                }
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
            availableModeratorsCount
          }
        }
      GQL
    end

    before(:once) do
      @ta = User.create!
      course.enroll_ta(@ta, enrollment_state: :active)
    end

    context "when user has permissions to manage assignments" do
      it "returns availableModerators and availableModeratorsCount" do
        result = execute_query

        expect(result["availableModerators"]["edges"]).to match_array [
          { "node" => { "_id" => @teacher.id.to_s, "name" => @teacher.name } },
          { "node" => { "_id" => @ta.id.to_s, "name" => @ta.name } },
        ]

        expect(result["availableModeratorsCount"]).to eq 2
      end

      it "paginate available moderators" do
        result = execute_query(pagination_options: { first: 1 })
        expect(result["availableModerators"]["edges"].length).to eq 1
        expect(result["availableModerators"]["pageInfo"]["hasNextPage"]).to be true

        end_cursor = result["availableModerators"]["pageInfo"]["endCursor"]
        result = execute_query(pagination_options: { first: 1, after: end_cursor })
        expect(result["availableModerators"]["edges"].length).to eq 1
        expect(result["availableModerators"]["pageInfo"]["hasNextPage"]).to be false
      end
    end

    context "when user does not have permissions to manage assignments" do
      it "returns nil" do
        result = execute_query(user: @student)
        expect(result["availableModerators"]).to be_nil
        expect(result["availableModeratorsCount"]).to be_nil
      end
    end
  end
end
