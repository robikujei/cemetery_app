# Current Schema Data Dictionary

This data dictionary matches the current Supabase schema and the intended app model: cemetery lots are grouped by `block_number`, each lot may contain multiple `graves`, and each grave may be linked to a `burial_record`. The old branch/section model is listed only as legacy because the app is moving to blocks.

## Operational Tables

### Table 1. Users

The `users` table replaces the old Visitor table. It stores all system accounts, including visitors, lot owners, gate officers, and administrators. The `role` field controls which screens and actions the user can access. The table also stores lot-owner profile and purchase/application details used by the admin and lot-owner modules.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| user_id | UUID | 16 | PK, NOT NULL | Unique identifier of the user account. |
| name | VARCHAR | 100 | NOT NULL | Display name or full name of the user. |
| email | VARCHAR | 100 | UNIQUE, NOT NULL | Email address used for login and account lookup. |
| password | VARCHAR | 255 | NOT NULL | Encrypted or hashed account password. |
| role | VARCHAR | 20 | NOT NULL | User role such as visitor, admin, guard, or lot_owner. |
| created_at | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Date and time the account was created. |
| phone | VARCHAR | 20 | NULLABLE | Contact number of the user. |
| control_number | TEXT | - | NULLABLE | Internal control or application number. |
| first_name | TEXT | - | NULLABLE | User first name. |
| middle_name | TEXT | - | NULLABLE | User middle name. |
| last_name | TEXT | - | NULLABLE | User last name. |
| address | TEXT | - | NULLABLE | Residential address. |
| occupation | TEXT | - | NULLABLE | User occupation. |
| age | INT | 32 | NULLABLE | User age. |
| civil_status | TEXT | - | NULLABLE | Civil status. |
| date_of_birth | DATE | - | NULLABLE | Date of birth. |
| gender | TEXT | - | NULLABLE | Gender. |
| spouse_beneficiary | TEXT | - | NULLABLE | Spouse or beneficiary name. |
| beneficiary_relationship | TEXT | - | NULLABLE | Relationship of beneficiary to the user. |
| lot_class_type | TEXT | - | NULLABLE | Selected or purchased lot class type. |
| block_number | TEXT | - | NULLABLE | Block number associated with the lot-owner application. |
| lot_number | TEXT | - | NULLABLE | Lot number associated with the lot-owner application. |
| number_of_lots | INT | 32 | NULLABLE | Number of lots requested or purchased. |
| purchase_term | TEXT | - | NULLABLE | Purchase or installment term. |
| lot_price | NUMERIC | 12,2 | NULLABLE | Lot price. |
| interment_fee | NUMERIC | 12,2 | NULLABLE | Interment fee. |
| certification_fee | NUMERIC | 12,2 | NULLABLE | Certification fee. |
| burial_permit_fee | NUMERIC | 12,2 | NULLABLE | Burial permit fee. |
| total_amount | NUMERIC | 12,2 | NULLABLE | Total amount due or paid. |
| or_number | TEXT | - | NULLABLE | Official receipt number. |
| receipt_amount | NUMERIC | 12,2 | NULLABLE | Amount shown on receipt. |
| receipt_date | DATE | - | NULLABLE | Receipt date. |
| approved_date | DATE | - | NULLABLE | Date the application or record was approved. |
| approved_by_name | TEXT | - | NULLABLE | Name of approving staff. |
| approval_signature | TEXT | - | NULLABLE | Stored approval signature or signature reference. |

### Table 2. Cemetery Lot

The `cemetery_lot` table stores each mapped cemetery lot. In the updated model, lots are grouped by `block_number` instead of cemetery sections. QGIS import fields such as `qgis_feature_id`, `polygon_geo`, and coordinate values allow the visitor and admin map screens to show lot shapes, labels, and selectable locations.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| lot_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the cemetery lot. |
| lot_number | VARCHAR | 50 | NOT NULL | Lot number or lot identifier. |
| section_id | INT | 32 | LEGACY FK, NULLABLE | Old reference to `section.section_id`; retained only until the section model is removed. |
| status | VARCHAR | 20 | NULLABLE | Lot status such as available, occupied, reserved, or unavailable. |
| price | NUMERIC | 10,2 | NOT NULL | Price of the lot. |
| x_coord | DOUBLE PRECISION | - | NOT NULL | Longitude or map X coordinate from the QGIS lot mapping. |
| y_coord | DOUBLE PRECISION | - | NOT NULL | Latitude or map Y coordinate from the QGIS lot mapping. |
| block_number | TEXT | - | NULLABLE | Current block grouping for the lot. This replaces section-based grouping in the app. |
| lot_class_type | TEXT | - | NULLABLE | Lot class or category imported from QGIS. |
| lot_label | TEXT | - | NULLABLE | Human-readable lot label shown on forms and map cards. |
| qgis_feature_id | TEXT | - | NULLABLE | Original QGIS feature identifier for traceability. |
| polygon_geo | JSONB | - | NULLABLE | GeoJSON polygon or geometry data used to draw the lot on the map. |

### Table 3. Graves

The `graves` table stores individual grave slots inside a cemetery lot. This supports lots that contain multiple graves. Visitor map cards use this table to let visitors choose the exact grave to navigate to after tapping a lot.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| grave_id | BIGINT | 64 | PK, NOT NULL | Unique identifier of the grave slot. |
| lot_id | INT | 32 | FK, NOT NULL | References `cemetery_lot.lot_id`. |
| grave_label | TEXT | - | NOT NULL | Grave label, number, or position within the lot. |
| status | TEXT | - | NOT NULL | Grave status such as available, occupied, reserved, or unavailable. |
| burial_id | INT | 32 | FK, NULLABLE | References `burial_record.burial_id` when the grave is occupied by a burial record. |
| notes | TEXT | - | NULLABLE | Administrative notes for the grave. |
| created_at | TIMESTAMPTZ | - | NOT NULL | Date and time the grave row was created. |
| updated_at | TIMESTAMPTZ | - | NOT NULL | Date and time the grave row was last updated. |

### Table 4. Burial Record

The `burial_record` table stores deceased-person and interment details. It supports visitor grave search, QR-based visitor logging, admin burial management, and the visitor map route flow. A burial can be linked to a lot directly through `lot_id` and, when available, to a specific grave through `graves.burial_id`.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| burial_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the burial record. |
| name_of_deceased | VARCHAR | 100 | NOT NULL | Full name of the deceased person. |
| birth_date | DATE | - | NULLABLE | Birth date of the deceased. |
| death_date | DATE | - | NOT NULL | Date of death. |
| burial_date | DATE | - | NULLABLE | Date of burial. |
| lot_id | INT | 32 | FK, NULLABLE | References `cemetery_lot.lot_id`. |
| application_date | DATE | - | NULLABLE | Date the burial or interment application was filed. |
| informant_id | BIGINT | 64 | FK, NULLABLE | References `burial_informants.informant_id`. |
| religion | TEXT | - | NULLABLE | Religion of the deceased. |
| interment_date | DATE | - | NULLABLE | Scheduled or actual interment date. |
| interment_time | TIME | - | NULLABLE | Scheduled or actual interment time. |
| burial_category | TEXT | - | NULLABLE | Burial category or service type. |
| bldg_no | TEXT | - | NULLABLE | Building number, if applicable. |
| niche_no | TEXT | - | NULLABLE | Niche number, if applicable. |
| level | TEXT | - | NULLABLE | Level or layer reference, if applicable. |
| lot_location_no | TEXT | - | NULLABLE | Lot or location number shown in records and search results. |
| registered_lot_owner | TEXT | - | NULLABLE | Registered lot owner name. |
| registered_owner_contact_no | TEXT | - | NULLABLE | Registered lot owner contact number. |
| interment_or_number | TEXT | - | NULLABLE | Official receipt number for interment payment. |
| interment_total | NUMERIC | 12,2 | NULLABLE | Total interment amount. |
| interment_payment_date | DATE | - | NULLABLE | Interment payment date. |
| death_certificate_submitted | BOOLEAN | - | NOT NULL | Indicates whether the death certificate was submitted. |
| ownership_certificate_submitted | BOOLEAN | - | NOT NULL | Indicates whether the ownership certificate was submitted. |
| authority_document_submitted | BOOLEAN | - | NOT NULL | Indicates whether the authority document was submitted. |

### Table 5. Burial Informants

The `burial_informants` table stores the informant or applicant details connected to a burial record. It helps the admin keep supporting information for interment applications.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| informant_id | BIGINT | 64 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the informant. |
| full_name | TEXT | - | NOT NULL | Full name of the informant. |
| relationship_to_deceased | TEXT | - | NULLABLE | Relationship of informant to the deceased. |
| address | TEXT | - | NULLABLE | Informant address. |
| work | TEXT | - | NULLABLE | Informant work or occupation. |
| cellphone_no | TEXT | - | NULLABLE | Informant cellphone number. |
| id_presented | TEXT | - | NULLABLE | Type of ID presented. |
| id_number | TEXT | - | NULLABLE | ID number. |
| place_issued | TEXT | - | NULLABLE | Place where the ID was issued. |
| created_at | TIMESTAMPTZ | - | NOT NULL | Date and time the informant record was created. |
| updated_at | TIMESTAMPTZ | - | NOT NULL | Date and time the informant record was last updated. |

### Table 6. Lot Ownership

The `lot_ownership` table connects a lot owner account to a cemetery lot. It supports ownership verification, installment monitoring, lot-owner dashboards, payment requests, and transaction history.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| ownership_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the ownership record. |
| lot_id | INT | 32 | FK, UNIQUE, NULLABLE | References `cemetery_lot.lot_id`. |
| user_id | UUID | 16 | FK, NULLABLE | References `users.user_id`. |
| total_months | INT | 32 | NOT NULL | Total installment months. |
| months_paid | INT | 32 | NULLABLE | Number of months already paid. |
| start_date | DATE | - | NOT NULL | Start date of ownership or installment term. |
| status | VARCHAR | 20 | NULLABLE | Ownership or payment status. |

### Table 7. Transaction History

The `transaction_history` table stores recorded payments connected to lot ownership. It is used for viewing paid records and payment summaries.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| transaction_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the transaction. |
| ownership_id | INT | 32 | FK, NULLABLE | References `lot_ownership.ownership_id`. |
| amount | NUMERIC | 10,2 | NOT NULL | Amount paid. |
| payment_date | DATE | - | NOT NULL | Date of payment. |
| notes | TEXT | - | NULLABLE | Notes about the transaction. |

### Table 8. Payment Requests

The `payment_requests` table stores payment requests and collection tracking records for lot ownership. Administrators can use it to monitor requested payments, receipts, and request status.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| request_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the payment request. |
| ownership_id | INT | 32 | FK, NULLABLE | References `lot_ownership.ownership_id`. |
| amount | NUMERIC | 10,2 | NOT NULL | Requested or expected payment amount. |
| payment_date | DATE | - | NOT NULL | Requested or target payment date. |
| receipt_url | TEXT | - | NULLABLE | URL or storage path of the receipt. |
| notes | TEXT | - | NULLABLE | User or request notes. |
| status | VARCHAR | 20 | NULLABLE | Request status such as pending, paid, approved, or rejected. |
| admin_notes | TEXT | - | NULLABLE | Internal administrator notes. |
| created_at | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Date and time the request was created. |
| updated_at | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Date and time the request was last updated. |

### Table 9. Visitor Log

The `visitor_log` table stores cemetery visit entries. It supports QR and manual check-in flows by recording the user, the burial being visited, check-in time, and logging method.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| log_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the visitor log entry. |
| burial_id | INT | 32 | FK, NULLABLE | References `burial_record.burial_id`. |
| user_id | UUID | 16 | FK, NULLABLE | References `users.user_id`. |
| time_in | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Time when the visitor checked in. |
| method | VARCHAR | 20 | NULLABLE | Check-in method such as QR or manual. |

### Table 10. Report

The `report` table stores generated report metadata. It supports admin reporting such as burial summaries, visitor logs, lot availability, transaction history, and activity monitoring.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| report_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the generated report. |
| report_type | VARCHAR | 50 | NOT NULL | Type of report generated. |
| description | TEXT | - | NULLABLE | Summary or description of the report. |
| generated_date | DATE | - | NOT NULL | Date the report was generated. |
| generated_by | UUID | 16 | FK, NULLABLE | References `users.user_id`. |

### Table 11. Audit Log

The `audit_log` table tracks system actions for monitoring, accountability, and troubleshooting. It is directly connected to `users` through `user_id`; `entity_type` and `entity_id` are polymorphic references that identify the affected record at the application level.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| log_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the audit entry. |
| user_id | UUID | 16 | FK, NULLABLE | References `users.user_id`. |
| user_email | VARCHAR | 100 | NULLABLE | Email of the acting user at the time of the action. |
| user_role | VARCHAR | 20 | NULLABLE | Role of the acting user at the time of the action. |
| action | VARCHAR | 50 | NOT NULL | Action performed, such as INSERT, UPDATE, DELETE, LOGIN, or LOGOUT. |
| entity_type | VARCHAR | 50 | NULLABLE | Table, module, or entity affected by the action. |
| entity_id | VARCHAR | 50 | NULLABLE | Identifier of the affected record. |
| details | TEXT | - | NULLABLE | JSON or text details of the action. |
| ip_address | VARCHAR | 50 | NULLABLE | IP address of the acting user, when available. |
| created_at | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Date and time of the audit entry. |

### Table 12. Cemetery Map

The `cemetery_map` table stores map configuration metadata. It provides the spatial reference used by the GIS map, including map image settings, real-world dimensions, entrance position, and geographic map bounds.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| map_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the map configuration. |
| map_image_url | TEXT | - | NOT NULL | URL or path of the cemetery map image. |
| map_width_meters | NUMERIC | 10,2 | NOT NULL | Real-world width of the map in meters. |
| map_height_meters | NUMERIC | 10,2 | NOT NULL | Real-world height of the map in meters. |
| uploaded_at | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Date and time the map was uploaded or configured. |
| entrance_x_percent | NUMERIC | 5,2 | NULLABLE | Main entrance X coordinate as a percentage. |
| entrance_y_percent | NUMERIC | 5,2 | NULLABLE | Main entrance Y coordinate as a percentage. |
| center_lat | DOUBLE PRECISION | - | NULLABLE | Latitude of the map center. |
| center_lng | DOUBLE PRECISION | - | NULLABLE | Longitude of the map center. |
| lat_span | DOUBLE PRECISION | - | NULLABLE | Latitude span used to calculate map bounds. |
| lng_span | DOUBLE PRECISION | - | NULLABLE | Longitude span used to calculate map bounds. |

### Table 13. Cemetery Map Features

The `cemetery_map_features` table stores QGIS-imported map features such as base map line art, boundaries, blocks, entrances, and pathways. Visitor map preview should show only non-pathway display features; pathway features are kept for navigation and route calculation when a visitor starts routing.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| feature_id | BIGINT | 64 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the map feature. |
| feature_type | TEXT | - | NOT NULL | Feature category such as map_layer, boundary, block, pathway, entrance, or other. |
| feature_name | TEXT | - | NULLABLE | Display name of the feature. |
| geometry_wkt | TEXT | - | NOT NULL | WKT geometry imported from QGIS. |
| stroke_color | TEXT | - | NULLABLE | Stroke or line color used for rendering. |
| fill_color | TEXT | - | NULLABLE | Fill color used for polygons. |
| stroke_width | NUMERIC | - | NULLABLE | Stroke width used for map rendering. |
| sort_order | INT | 32 | NOT NULL | Drawing order of the feature. |
| is_visible | BOOLEAN | - | NOT NULL | Whether the feature is generally enabled for display. |
| source_feature_id | TEXT | - | NULLABLE | Original QGIS feature identifier. |
| created_at | TIMESTAMPTZ | - | NOT NULL | Date and time the feature was imported. |

### Table 14. Lot Markers

The `lot_markers` table stores percentage-based marker coordinates for cemetery lots. These markers support clickable map behavior, lot selection, and navigation target positioning.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| marker_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the marker. |
| lot_id | INT | 32 | FK, NULLABLE | References `cemetery_lot.lot_id`. |
| x_percent | NUMERIC | 5,2 | NOT NULL | X position on the map as a percentage. |
| y_percent | NUMERIC | 5,2 | NOT NULL | Y position on the map as a percentage. |
| created_at | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Date and time the marker was created. |

### Table 15. Path Nodes

The `path_nodes` table stores graph nodes used by the navigation system. These nodes are used internally by Dijkstra pathfinding and should not be shown as always-visible visitor map preview features.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| node_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the path node. |
| x_percent | NUMERIC | 5,2 | NOT NULL | X position on the map as a percentage. |
| y_percent | NUMERIC | 5,2 | NOT NULL | Y position on the map as a percentage. |
| node_type | VARCHAR | 20 | NULLABLE | Node type such as normal, entrance, exit, or landmark. |
| created_at | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Date and time the node was created. |

### Table 16. Path Edges

The `path_edges` table stores graph connections between path nodes. It provides the weighted edges needed by Dijkstra's shortest path algorithm.

| Field Name | Data Type | Length/Precision | Constraint | Description |
| --- | --- | --- | --- | --- |
| edge_id | INT | 32 | PK, AUTO INCREMENT, NOT NULL | Unique identifier of the path edge. |
| from_node_id | INT | 32 | FK, NULLABLE | Starting node, references `path_nodes.node_id`. |
| to_node_id | INT | 32 | FK, NULLABLE | Ending node, references `path_nodes.node_id`. |
| distance_meters | NUMERIC | 10,2 | NULLABLE | Real-world distance between the two nodes. |
| created_at | TIMESTAMP | - | DEFAULT CURRENT_TIMESTAMP | Date and time the edge was created. |

## Import and Staging Tables

### Table 17. Lot Import Staging

The `lot_import_staging` table temporarily stores QGIS lot CSV data before it is imported into `cemetery_lot` and `lot_markers`. It is not a runtime app table, but it should be kept while QGIS imports are still being used.

| Field Name | Data Type | Description |
| --- | --- | --- |
| qgis_feature_id | TEXT | QGIS feature identifier. |
| block_number | TEXT | Block number imported from QGIS. |
| lot_number | TEXT | Lot number imported from QGIS. |
| lot_label | TEXT | Display label imported from QGIS. |
| lot_class_type | TEXT | Lot class or type. |
| price | NUMERIC | Lot price from import file. |
| status | TEXT | Lot status from import file. |
| lon | DOUBLE PRECISION | Longitude value. |
| lat | DOUBLE PRECISION | Latitude value. |
| polygon_geo | JSONB | Lot polygon geometry. |
| fid | TEXT | Alternative feature ID from QGIS. |
| xcoord | TEXT | Alternative X coordinate field. |
| ycoord | TEXT | Alternative Y coordinate field. |
| x | TEXT | Alternative X field. |
| y | TEXT | Alternative Y field. |

### Table 18. Map Feature Import Staging

The `map_feature_import_staging` table temporarily stores QGIS WKT feature exports before they are imported into `cemetery_map_features`.

| Field Name | Data Type | Description |
| --- | --- | --- |
| feature_type | TEXT | Feature type from QGIS or import file. |
| feature_name | TEXT | Feature display name. |
| name | TEXT | Alternative feature name column. |
| block_number | TEXT | Block value, if the feature represents a block. |
| fid | TEXT | Alternative feature ID from QGIS. |
| qgis_feature_id | TEXT | QGIS feature identifier. |
| geometry_wkt | TEXT | WKT geometry. |
| wkt | TEXT | Alternative WKT column. |
| stroke_color | TEXT | Stroke color for rendering. |
| fill_color | TEXT | Fill color for rendering. |
| stroke_width | NUMERIC | Stroke width for rendering. |
| sort_order | INT | Drawing order. |
| is_visible | BOOLEAN | Whether the feature should be visible after import. |

## Legacy or Optional Tables Still Present in the Database

These tables still exist in the current database output, but they do not represent the intended new block-based model.

### Table 19. Cemetery Branch

The `cemetery_branch` table is part of the old branch and section design. The new app flow uses one cemetery map configuration through `cemetery_map` and groups lots by `cemetery_lot.block_number`.

| Field Name | Data Type | Constraint | Description |
| --- | --- | --- | --- |
| branch_id | INT | PK, AUTO INCREMENT, NOT NULL | Legacy branch identifier. |
| name | VARCHAR(100) | NOT NULL | Legacy cemetery branch name. |
| map_image | TEXT | NOT NULL | Legacy map image reference. |
| entrances | JSONB | NULLABLE | Legacy entrance coordinates. |
| exits | JSONB | NULLABLE | Legacy exit coordinates. |

### Table 20. Section

The `section` table is part of the old cemetery section model. The current app model replaces sections with blocks stored in `cemetery_lot.block_number`. This table remains only because `cemetery_lot.section_id` still has a database-level foreign key.

| Field Name | Data Type | Constraint | Description |
| --- | --- | --- | --- |
| section_id | INT | PK, AUTO INCREMENT, NOT NULL | Legacy section identifier. |
| name | VARCHAR(50) | NOT NULL | Legacy section name. |
| coordinates | JSONB | NOT NULL | Legacy section polygon or coordinate data. |
| branch_id | INT | FK, NULLABLE | References `cemetery_branch.branch_id`. |

### Table 21. Walkways

The `walkways` table stores a simpler polyline-style walkway representation. The current routing implementation uses `path_nodes`, `path_edges`, and QGIS `cemetery_map_features` pathway rows instead.

| Field Name | Data Type | Constraint | Description |
| --- | --- | --- | --- |
| walkway_id | INT | PK, AUTO INCREMENT, NOT NULL | Unique walkway identifier. |
| name | VARCHAR(100) | NULLABLE | Walkway name. |
| points | JSONB | NOT NULL | Array of coordinate points. |
| width | NUMERIC(5,2) | NULLABLE | Walkway width. |
| created_at | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP | Date and time the walkway row was created. |

## Main Relationships

| Relationship | Description |
| --- | --- |
| `cemetery_lot.lot_id` to `graves.lot_id` | One lot can contain multiple graves. |
| `graves.burial_id` to `burial_record.burial_id` | A grave can be linked to one burial record. |
| `burial_record.lot_id` to `cemetery_lot.lot_id` | A burial record can also be linked directly to a lot for search and older records. |
| `burial_record.informant_id` to `burial_informants.informant_id` | A burial record can have one informant. |
| `lot_ownership.lot_id` to `cemetery_lot.lot_id` | A lot can have one ownership record. |
| `lot_ownership.user_id` to `users.user_id` | A user can own or be assigned to lot ownership records. |
| `transaction_history.ownership_id` to `lot_ownership.ownership_id` | Ownership records can have payment transaction history. |
| `payment_requests.ownership_id` to `lot_ownership.ownership_id` | Ownership records can have payment requests. |
| `visitor_log.burial_id` to `burial_record.burial_id` | Visitor check-ins can be linked to a burial record. |
| `visitor_log.user_id` to `users.user_id` | Visitor check-ins can be linked to a user account. |
| `audit_log.user_id` to `users.user_id` | Audit entries can be linked to the acting user. |
| `path_edges.from_node_id` and `path_edges.to_node_id` to `path_nodes.node_id` | Path edges connect navigation nodes for route calculation. |

