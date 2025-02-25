/*
 * Copyright (C) 2024 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import type {Rubric, RubricAssessmentData, RubricCriterion} from '../../types/rubric'

export const RUBRIC_DATA: Pick<Rubric, 'title' | 'ratingOrder' | 'pointsPossible'> & {
  criteria: RubricCriterion[]
} = {
  title: 'Rubric Title',
  pointsPossible: 14,
  criteria: [
    {
      id: '1',
      description: 'Criteria 1',
      criterionUseRange: true,
      ignoreForScoring: false,
      longDescription: '',
      masteryPoints: 0,
      points: 4,
      ratings: [
        {
          id: '4',
          description: 'Rating 4',
          points: 4,
          longDescription: 'exceptional work',
        },
        {
          id: '3',
          description: 'Rating 3',
          points: 3,
          longDescription: 'great work',
        },
        {
          id: '2',
          description: 'Rating 2',
          points: 2,
          longDescription: 'mid',
        },
        {
          id: '1',
          description: 'Rating 1',
          points: 1,
          longDescription: '',
        },
        {
          id: '0',
          description: 'Rating 2\0',
          points: 0,
          longDescription: '',
        },
      ],
    },
    {
      id: '2',
      description: 'Criteria 2',
      criterionUseRange: false,
      ignoreForScoring: false,
      longDescription: '',
      masteryPoints: 0,
      points: 10,
      ratings: [
        {
          id: '10',
          description: 'Rating 10',
          points: 10,
          longDescription: 'amazing work',
        },
        {
          id: '00',
          description: 'Rating 00',
          points: 0,
          longDescription: '',
        },
      ],
    },
  ],
  ratingOrder: 'descending',
}

export const SELF_ASSESSMENT_DATA: RubricAssessmentData[] = [
  {
    id: '3',
    comments: 'Self Assessment Comment 1',
    criterionId: '1',
    points: 3,
    description: 'Rating 3',
    commentsEnabled: true,
  },
  {
    id: '10',
    comments: '',
    criterionId: '2',
    points: 10,
    description: 'Rating 10',
    commentsEnabled: true,
  },
]

export const TEACHER_ASSESSMENT_DATA: RubricAssessmentData[] = [
  {
    id: '2',
    comments: 'I graded this as a 2',
    criterionId: '1',
    points: 2,
    description: 'Rating 2',
    commentsEnabled: true,
  },
]
