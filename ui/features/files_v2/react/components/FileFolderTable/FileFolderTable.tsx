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

import React, {useState} from 'react'
import {useScope as createI18nScope} from '@canvas/i18n'
import {Link} from '@instructure/ui-link'
import {Table} from '@instructure/ui-table'
import {Text} from '@instructure/ui-text'
import FriendlyDatetime from '@canvas/datetime/react/components/FriendlyDatetime'
import friendlyBytes from '@canvas/files/util/friendlyBytes'
import {TruncateText} from '@instructure/ui-truncate-text'
import {showFlashError} from '@canvas/alerts/react/FlashAlert'
import {useQuery} from '@canvas/query'

import {type File, type Folder} from '../../../interfaces/File'
import {type ColumnHeader} from '../../../interfaces/FileFolderTable'
import {parseLinkHeader} from '../../../utils/apiUtils'
import SubTableContent from './SubTableContent'
import ActionMenuButton from './ActionMenuButton'
import NameLink from './NameLink'
import PublishIconButton from './PublishIconButton'
import RightsIconButton from './RightsIconButton'
import renderTableHead from './RenderTableHead'
import renderTableBody from './RenderTableBody'

const I18n = createI18nScope('files_v2')

const fetchFilesAndFolders = async (
  url: string,
  onLoadingStatusChange: (arg0: boolean) => void,
) => {
  onLoadingStatusChange(true)
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error('Failed to fetch files and folders')
  }
  const links = parseLinkHeader(response.headers.get('Link'))
  const rows = await response.json()
  return {rows, links}
}

const columnHeaders: ColumnHeader[] = [
  {id: 'name', title: I18n.t('Name'), textAlign: 'start', width: '12.5em'},
  {id: 'created', title: I18n.t('Created'), textAlign: 'start', width: '6em'},
  {id: 'lastModified', title: I18n.t('Last Modified'), textAlign: 'start', width: '6em'},
  {id: 'modifiedBy', title: I18n.t('Modified By'), textAlign: 'start', width: '6em'},
  {id: 'size', title: I18n.t('Size'), textAlign: 'start', width: '4em'},
  {id: 'rights', title: I18n.t('Rights'), textAlign: 'center', width: '3.5em'},
  {id: 'published', title: I18n.t('Published'), textAlign: 'center', width: '4em'},
  {id: 'actions', title: '', textAlign: 'center', width: '3em'},
]

const columnRenderers: {
  [key: string]: (
    row: File | Folder,
    isStacked: boolean,
    userCanEditFilesForContext: boolean,
    usageRightsRequiredForContext: boolean,
    size: 'small' | 'medium' | 'large',
    isSelected: boolean,
    toggleSelect: () => void,
  ) => React.ReactNode
} = {
  name: (row, isStacked) => <NameLink isStacked={isStacked} item={row} />,
  created: row => <FriendlyDatetime dateTime={row.created_at} />,
  lastModified: row => <FriendlyDatetime dateTime={row.updated_at} />,
  modifiedBy: row =>
    'user' in row && row.user?.display_name ? (
      <Link isWithinText={false} href={row.user.html_url}>
        <TruncateText>{row.user.display_name}</TruncateText>
      </Link>
    ) : null,
  size: row =>
    'size' in row ? <Text>{friendlyBytes(row.size)}</Text> : <Text>{I18n.t('--')}</Text>,
  rights: (row, _isStacked, userCanEditFilesForContext, usageRightsRequiredForContext) =>
    row.folder_id && usageRightsRequiredForContext ? (
      <RightsIconButton
        usageRights={row.usage_rights}
        userCanEditFilesForContext={userCanEditFilesForContext}
      />
    ) : null,
  published: (row, _isStacked, userCanEditFilesForContext) => (
    <PublishIconButton item={row} userCanEditFilesForContext={userCanEditFilesForContext} />
  ),
  actions: (_row, isStacked) => <ActionMenuButton isStacked={isStacked} />,
}

interface FileFolderTableProps {
  size: 'small' | 'medium' | 'large'
  userCanEditFilesForContext: boolean
  usageRightsRequiredForContext: boolean
  currentUrl: string
  onPaginationLinkChange: (links: Record<string, string>) => void
  onLoadingStatusChange: (isLoading: boolean) => void
}

const FileFolderTable = ({
  size,
  userCanEditFilesForContext,
  usageRightsRequiredForContext,
  currentUrl,
  onPaginationLinkChange,
  onLoadingStatusChange,
}: FileFolderTableProps) => {
  const isStacked = size !== 'large'

  const {data, error, isLoading, isFetching} = useQuery({
    queryKey: ['files', currentUrl],
    queryFn: () => fetchFilesAndFolders(currentUrl, onLoadingStatusChange),
    staleTime: 0,
    onSuccess: ({links}) => {
      onPaginationLinkChange(links)
    },
    onSettled: () => {
      onLoadingStatusChange(false)
    },
  })

  if (error) {
    showFlashError(I18n.t('Failed to fetch files and folders'))
  }

  const rows: (File | Folder)[] = !isFetching && data?.rows && data.rows.length > 0 ? data.rows : []

  const [selectedRows, setSelectedRows] = useState<Set<string>>(new Set())

  const toggleRowSelection = (rowId: string) => {
    setSelectedRows(prev => {
      const newSet = new Set(prev)
      if (newSet.has(rowId)) {
        newSet.delete(rowId)
      } else {
        newSet.add(rowId)
      }
      return newSet
    })
  }

  const toggleSelectAll = () => {
    if (selectedRows.size === rows.length) {
      setSelectedRows(new Set()) // Unselect all
    } else {
      setSelectedRows(new Set(rows.map(row => row.id))) // Select all
    }
  }

  const allRowsSelected = rows.length != 0 && selectedRows.size === rows.length
  const someRowsSelected = selectedRows.size > 0 && !allRowsSelected
  const filteredColumns = columnHeaders.filter(column => {
    if (column.id === 'rights') {
      return usageRightsRequiredForContext
    }
    return true
  })

  return (
    <>
      <Table
        caption={I18n.t('Files and Folders')}
        hover={true}
        layout={isStacked ? 'stacked' : 'fixed'}
      >
        <Table.Head>
          <Table.Row>
            {renderTableHead(
              size,
              allRowsSelected,
              someRowsSelected,
              toggleSelectAll,
              isStacked,
              filteredColumns,
            )}
          </Table.Row>
        </Table.Head>
        <Table.Body>
          {renderTableBody(
            rows,
            filteredColumns,
            selectedRows,
            size,
            isStacked,
            columnRenderers,
            toggleRowSelection,
            userCanEditFilesForContext,
            usageRightsRequiredForContext,
          )}
        </Table.Body>
      </Table>
      <SubTableContent
        isLoading={isLoading || isFetching}
        isEmpty={rows.length === 0 && !isFetching}
      />
    </>
  )
}

export default FileFolderTable
