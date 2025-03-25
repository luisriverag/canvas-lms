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

import filesEnv from '@canvas/files_v2/react/modules/filesEnv'
import {windowPathname} from '@canvas/util/globalUtils'

const SEARCH_AND_ALL_QUERY_PARAMS =
  'per_page=25&include[]=user&include[]=usage_rights&include[]=enhanced_preview_url&include[]=context_asset_string&include[]=blueprint_course_status'
interface TableUrlParams {
  searchTerm: string
  contextType: string
  contextId: string
  folderId: string
  sortBy: string
  sortDirection: string
  pageQueryParam?: string
}

export const generateFolderByPathUrl = (pluralContextType: string, contextId: string, path?: string) => {
  const baseUrl = `/api/v1/${pluralContextType}/${contextId}/folders/by_path`
  if (!path) {
    return baseUrl
  }

  const encodedPath = encodeURIComponent(path).replace(/%2F/g, '/')
  return `${baseUrl}/${encodedPath}`
}

export const generateFilesQuotaUrl = (singularContextType: string, contextId: string) => {
  return `/api/v1/${singularContextType}s/${contextId}/files/quota`
}

export const generateFolderPostUrl = (parentFolderId: string) => {
  return `/api/v1/folders/${parentFolderId}/folders`
}

export const generateTableUrl = ({
  searchTerm,
  contextType,
  contextId,
  folderId,
  sortBy,
  sortDirection,
  pageQueryParam,
}: TableUrlParams) => {
  const baseUrl = searchTerm
    ? generateSearchUrl(contextType, contextId, searchTerm)
    : generateFetchAllUrl(folderId)
  const sortedUrl = `${baseUrl}&sort=${sortBy}&order=${sortDirection}`
  return pageQueryParam ? `${sortedUrl}&page=${pageQueryParam}` : sortedUrl
}

export const generateSearchNavigationUrl = (searchValue: string) => {
  const path = windowPathname()
  const pluralContext = path.split('/')[3]
  return filesEnv.showingAllContexts
    ? `/folder/${pluralContext}?search_term=${searchValue}`
    : `/?search_term=${searchValue}`
}

export const parseLinkHeader = (header: string | null) => {
  if (!header) return {}
  const links: Record<string, string> = {}
  header.split(',').forEach(part => {
    const match = part.match(/<(.*?)>; rel="(.*?)"/)
    if (match) {
      const [, url, rel] = match
      links[rel] = url
    }
  })
  return links
}

const generateSearchUrl = (singularContextType: string, contextId: string, searchTerm: string) => {
  return `/api/v1/${singularContextType}s/${contextId}/files?search_term=${searchTerm}&${SEARCH_AND_ALL_QUERY_PARAMS}`
}

const generateFetchAllUrl = (folderId: string) => {
  return `/api/v1/folders/${folderId}/all?${SEARCH_AND_ALL_QUERY_PARAMS}`
}
