# frozen_string_literal: true

#
# Copyright (C) 2012 - present Instructure, Inc.
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

class Quizzes::QuizQuestion::FileUploadAnswer < Quizzes::QuizQuestion::UserAnswer
  def initialize(question_id, points_possible, answer_data)
    super
    self.answer_details = { attachment_ids: }
  end

  def attachment_ids
    return nil unless (data = @answer_data[:"question_#{question_id}"])

    ids = data.compact_blank
    ids.presence
  end
end
