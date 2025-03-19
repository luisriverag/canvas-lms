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
import React from 'react'
import {Flex} from '@instructure/ui-flex'
import {Button} from '@instructure/ui-buttons'
import FilterDropDown from '../FilterDropDown/FilterDropDown'
import {Text} from '@instructure/ui-text'
import InsightsSearchBar from '../InsightsSearchBar/InsightsSearchBar'
import AiIcon from '@canvas/ai-icon'
import {useScope as createI18nScope} from '@canvas/i18n'

const I18n = createI18nScope('discussion_insights')

type InsightsActionBarProps = {
  handleSearch: (query: string) => void
}

const InsightsActionBar: React.FC<InsightsActionBarProps> = ({handleSearch}) => {
  return (
    <Flex width="100%" direction="row" wrap="wrap" gap="small">
      <Flex.Item shouldGrow shouldShrink>
        <InsightsSearchBar onSearch={handleSearch} />
      </Flex.Item>
      <Flex.Item shouldShrink shouldGrow={false} width="fit-content">
        <FilterDropDown
          onFilterClick={() => {
            //TODO: will be implemented in VICE-5147
          }}
        />
      </Flex.Item>
      <Flex.Item>
        <Button
          display="inline-block"
          color="primary"
          renderIcon={<AiIcon />}
          onClick={() => {
            //TODO: will be implemented in VICE-5151
          }}
          data-testid="discussion-insights-generate-button"
        >
          <Text>{I18n.t('Generate Insights')}</Text>
        </Button>
      </Flex.Item>
    </Flex>
  )
}

export default InsightsActionBar
