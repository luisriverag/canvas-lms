/*
 * Copyright (C) 2025 - present Instructure, Inc.
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

import {render} from '@testing-library/react'
import ReportDescription from '../account_reports/ReportDescription'

const props = {
  descHTML: '<h1>Report Description</h1>',
  title: 'Report Title',
  closeModal: jest.fn(),
}

describe('ReportDescription', () => {
  it('renders inner html correctly', () => {
    const {getByText} = render(<ReportDescription {...props} />)

    expect(getByText('Report Description')).toBeInTheDocument()
    expect(getByText('Report Title')).toBeInTheDocument()
  })
})
