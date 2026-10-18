import '../../core/app_colors.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/analytics_data.dart';
import '../../services/cemetery_analytics.dart';
import '../../services/audit_service.dart';
import '../../utils/csv_download.dart';
import '../../utils/lot_formatters.dart';
import '../../utils/map_feature_geometry.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});
  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  AnalyticsData? _data;
  bool _loading = false, _exporting = false;
  DateTimeRange? _range;
  TrendInterval _interval = TrendInterval.daily;
  double _epsilon = 15, _medium = 30, _high = 70;
  int _minPoints = 5;
  String _report = 'Burial records';
  SpatialResult _spatial = const SpatialResult([], [], 0, 0);
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  static const _mockEnabled = bool.fromEnvironment(
    'MOCK_ANALYTICS',
    defaultValue: false,
  );
  static const _accent = AppColors.brand;
  static const _types = [
    'Burial records',
    'Visitor logs',
    'Visitor trends',
    'Lot inventory',
    'Lot sales',
    'Payments',
    'Lot demand',
    'Hotspot analysis',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    if (_mockEnabled) return;
    var channel = Supabase.instance.client.channel('reports-monitoring');
    for (final table in [
      'cemetery_lot',
      'burial_record',
      'visitor_log',
      'lot_ownership',
      'transaction_history',
      'cemetery_map_features',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          _refreshTimer?.cancel();
          _refreshTimer = Timer(const Duration(seconds: 1), _load);
        },
      );
    }
    _channel = channel.subscribe();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final data = _mockEnabled
        ? AnalyticsData.mock()
        : await AnalyticsData.load(Supabase.instance.client);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _calculate();
    });
  }

  void _calculate() {
    _spatial =
        _data?.spatial(
          start: _range?.start,
          end: _range?.end,
          epsilon: _epsilon,
          minPoints: _minPoints,
        ) ??
        const SpatialResult([], [], 0, 0);
  }

  bool _included(Object? value) => inPeriod(value, _range?.start, _range?.end);
  List<BlockDemand> get _demand => classifyDemand(_data!.lots, _data!.sales);
  Map<DateTime, int> get _trend => visitorTrend(
    _data!.visitors,
    _interval,
    start: _range?.start,
    end: _range?.end,
  );
  Widget _densitySummary() {
    final areas = _data!.mappedLotAreas();
    final counts = <String, int>{};
    for (final point in _spatial.points) {
      counts[point.block] = (counts[point.block] ?? 0) + 1;
    }
    final densities = {
      for (final e in areas.entries)
        e.key: (counts[e.key] ?? 0) * 10000 / e.value,
    };
    final values = densities.values.toList();
    final mean = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a + b) / values.length;
    final variance = values.isEmpty
        ? 0.0
        : values.fold<double>(0, (s, v) => s + (v - mean) * (v - mean)) /
              values.length;
    final threshold = mean + 2 * math.sqrt(variance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Block density uses burials per hectare of mapped lot footprint; walkways and unmapped land are excluded. '
          'The paper’s mean + 2 standard deviations rule is an exploratory comparison, not a significance test.',
        ),
        Text(
          values.length < 3
              ? 'At least three mapped blocks are needed for density comparison.'
              : 'High-density threshold: ${threshold.toStringAsFixed(1)} burials per mapped hectare.',
        ),
        _table(
          [
            'Block',
            'Burials',
            'Mapped m²',
            'Burials/hectare',
            'Above threshold',
          ],
          densities.entries
              .map(
                (e) => [
                  e.key,
                  counts[e.key] ?? 0,
                  areas[e.key]!.toStringAsFixed(1),
                  e.value.toStringAsFixed(1),
                  values.length < 3
                      ? 'Not assessed'
                      : e.value > threshold
                      ? 'Yes'
                      : 'No',
                ],
              )
              .toList(),
        ),
      ],
    );
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (range != null && mounted) {
      setState(() {
        _range = range;
        _calculate();
      });
    }
  }

  Widget _card(String title, Widget child) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: _accent,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
  Widget _table(List<String> headers, List<List<Object?>> rows) {
    if (rows.isEmpty) return const Text('No matching records.');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
        rows: rows
            .take(100)
            .map(
              (row) => DataRow(
                cells: row
                    .map((c) => DataCell(Text(c?.toString() ?? '—')))
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const Center(child: CircularProgressIndicator());
    final data = _data!;
    final demands = _demand;
    final trend = _trend;
    final maxCount = trend.values.fold<int>(1, math.max);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_loading) const LinearProgressIndicator(),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  _range == null
                      ? 'All dates'
                      : '${DateFormat.yMMMd().format(_range!.start)} – ${DateFormat.yMMMd().format(_range!.end)}',
                ),
              ),
              if (_range != null)
                TextButton(
                  onPressed: () => setState(() {
                    _range = null;
                    _calculate();
                  }),
                  child: const Text('Clear dates'),
                ),
              IconButton(
                onPressed: _loading ? null : _load,
                tooltip: 'Refresh data',
                icon: const Icon(Icons.refresh),
              ),
              Text('Updated ${DateFormat.Hm().format(data.loadedAt!)}'),
              if (_mockEnabled)
                const Chip(
                  avatar: Icon(Icons.science_outlined, size: 16),
                  label: Text('Demo data'),
                ),
            ],
          ),
          if (_mockEnabled)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Showing sample reports and analytics. This data is local and is not connected to Supabase.',
              ),
            ),
          const SizedBox(height: 12),
          if (data.errors.isNotEmpty)
            _card(
              'Some data could not be loaded',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Affected reports are unavailable. Refresh to retry.',
                  ),
                  ...data.errors.entries.map(
                    (e) => Text('${e.key}: ${e.value}'),
                  ),
                ],
              ),
            ),
          _card(
            'Export reports',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<String>(
                      value: _report,
                      items: _types
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _report = value!),
                    ),
                    FilledButton.icon(
                      onPressed: _loading || _exporting ? null : _export,
                      icon: const Icon(Icons.download),
                      label: Text(_exporting ? 'Exporting…' : 'Download CSV'),
                    ),
                  ],
                ),
                const Text(
                  'Dates include the whole end day. Inventory and demand show the current state; '
                  'sales use ownership start dates, payments use payment dates, and burials use interment/burial dates. '
                  'Visitor dates use Philippine time. Tables show up to 100 rows; exports include all matching rows.',
                ),
              ],
            ),
          ),
          if (!data.errors.containsKey('transaction_history'))
            _card(
              'Recorded payments',
              Text(
                'PHP ${NumberFormat('#,##0.00').format(data.payments.where((p) => _included(p['payment_date'])).fold<double>(0, (s, p) => s + number(p['amount'])))} '
                'across ${data.payments.where((p) => _included(p['payment_date'])).length} transactions in this period.',
              ),
            ),
          if (!data.errors.containsKey('visitor_log'))
            _card(
              'Visitor trends',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: TrendInterval.values
                        .map(
                          (v) => ChoiceChip(
                            label: Text(v.name),
                            selected: _interval == v,
                            onSelected: (_) => setState(() => _interval = v),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${trend.values.fold<int>(0, (s, v) => s + v)} entries. Weeks start Monday; empty periods count as zero.',
                  ),
                  const SizedBox(height: 12),
                  if (trend.isEmpty)
                    const Text('No visitor entries in this period.'),
                  ...trend.entries
                      .toList()
                      .reversed
                      .take(24)
                      .toList()
                      .reversed
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 100,
                                child: Text(
                                  DateFormat('yyyy-MM-dd').format(e.key),
                                ),
                              ),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: e.value / maxCount,
                                  minHeight: 12,
                                  color: _accent,
                                  backgroundColor: AppColors.surfaceHighest,
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                child: Text(
                                  '${e.value}',
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (trend.length > 24)
                    const Text(
                      'Chart shows the latest 24 periods. Export for the full history.',
                    ),
                ],
              ),
            ),
          if (!data.errors.containsKey('cemetery_lot') &&
              !data.errors.containsKey('lot_ownership'))
            _card(
              'Current lot demand',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Demand indicator = lots occupied or sold ÷ total lots in each block. '
                    'A sold and occupied lot counts once. This describes current uptake, not future sales.',
                  ),
                  Wrap(
                    spacing: 24,
                    children: [
                      SizedBox(
                        width: 230,
                        child: Column(
                          children: [
                            Text('Medium from ${_medium.round()}%'),
                            Slider(
                              value: _medium,
                              min: 5,
                              max: 65,
                              divisions: 12,
                              onChanged: (v) => setState(() => _medium = v),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: Column(
                          children: [
                            Text('High from ${_high.round()}%'),
                            Slider(
                              value: _high,
                              min: 70,
                              max: 100,
                              divisions: 6,
                              onChanged: (v) => setState(() => _high = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    children: ['High', 'Medium', 'Low']
                        .map(
                          (level) => Chip(
                            avatar: CircleAvatar(
                              backgroundColor: level == 'High'
                                  ? Colors.red
                                  : level == 'Medium'
                                  ? Colors.orange
                                  : _accent,
                              radius: 5,
                            ),
                            label: Text(
                              '$level: ${demands.where((d) => d.level(medium: _medium, high: _high) == level).length} blocks',
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  _table(
                    [
                      'Block',
                      'Lots',
                      'Occupied',
                      'Available',
                      'Sold',
                      'Uptake',
                      'Demand',
                    ],
                    demands
                        .map(
                          (d) => [
                            d.block,
                            d.lots,
                            d.occupied,
                            d.available,
                            d.sold,
                            '${d.score.toStringAsFixed(1)}%',
                            d.level(medium: _medium, high: _high),
                          ],
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          if (!data.errors.containsKey('cemetery_lot') &&
              !data.errors.containsKey('burial_record'))
            _card(
              'Spatial burial hotspots',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DBSCAN groups nearby burial records. Multiple burials in one lot share its mapped location. '
                    'Gray points are isolated records; colored points belong to clusters.',
                  ),
                  Wrap(
                    spacing: 24,
                    children: [
                      SizedBox(
                        width: 260,
                        child: Column(
                          children: [
                            Text('Radius: ${_epsilon.round()} metres'),
                            Slider(
                              value: _epsilon,
                              min: 5,
                              max: 100,
                              divisions: 19,
                              onChanged: (v) => setState(() {
                                _epsilon = v;
                                _calculate();
                              }),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: Column(
                          children: [
                            Text(
                              'Minimum nearby burials: $_minPoints (including itself)',
                            ),
                            Slider(
                              value: _minPoints.toDouble(),
                              min: 2,
                              max: 30,
                              divisions: 28,
                              onChanged: (v) => setState(() {
                                _minPoints = v.round();
                                _calculate();
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_spatial.clusterCount} clusters · ${_spatial.noiseCount} isolated records · '
                    '${_spatial.excluded} records excluded for missing geographic locations.',
                  ),
                  if (_range != null)
                    const Text(
                      'Records without a burial/interment date are excluded from this date range.',
                    ),
                  const SizedBox(height: 12),
                  _hotspotMap(),
                  _densitySummary(),
                  const SizedBox(height: 12),
                  _table(
                    ['Cluster', 'Burials', 'Blocks'],
                    [
                      for (var c = 0; c < _spatial.clusterCount; c++)
                        [
                          c + 1,
                          _spatial.labels.where((l) => l == c).length,
                          {
                            for (var i = 0; i < _spatial.points.length; i++)
                              if (_spatial.labels[i] == c)
                                _spatial.points[i].block,
                          }.join(', '),
                        ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _hotspotMap() {
    final positions = _data!.lots
        .map(_data!.position)
        .whereType<LatLng>()
        .toList();
    if (positions.isEmpty) {
      return const Text(
        'Import geographic lot polygons or QGIS coordinates to display the analysis map.',
      );
    }
    const colors = [
      Colors.red,
      Colors.deepOrange,
      Colors.purple,
      Colors.blue,
      Colors.teal,
    ];
    final points = _spatial.points;
    final byLocation = <String, int>{};
    for (var i = 0; i < points.length; i++) {
      byLocation[points[i].lotId] = i;
    }
    return SizedBox(
      height: 420,
      child: FlutterMap(
        key: ValueKey(_data!.loadedAt),
        options: MapOptions(
          initialCenter: positions.first,
          initialZoom: 18,
          initialCameraFit: positions.length > 1
              ? CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(positions),
                  padding: const EdgeInsets.all(30),
                  maxZoom: 19,
                )
              : null,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'cemetery_app',
          ),
          PolygonLayer(
            polygons: lotPolygonsFromLots(_data!.lots, lowDetail: true),
          ),
          CircleLayer(
            circles: byLocation.values
                .map(
                  (i) => CircleMarker(
                    point: LatLng(points[i].lat, points[i].lng),
                    radius: _spatial.labels[i] < 0 ? 3 : 7,
                    color:
                        (_spatial.labels[i] < 0
                                ? Colors.grey
                                : colors[_spatial.labels[i] % colors.length])
                            .withValues(alpha: 0.65),
                    borderColor: Colors.white,
                    borderStrokeWidth: 1,
                  ),
                )
                .toList(),
          ),
          const RichAttributionWidget(
            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final data = _data!;
      final requiredTables = switch (_report) {
        'Burial records' => ['burial_record', 'cemetery_lot'],
        'Visitor logs' || 'Visitor trends' => ['visitor_log'],
        'Lot inventory' => ['cemetery_lot'],
        'Lot sales' => ['lot_ownership', 'cemetery_lot'],
        'Payments' => ['transaction_history'],
        'Lot demand' => ['cemetery_lot', 'lot_ownership'],
        _ => ['cemetery_lot', 'burial_record'],
      };
      if (requiredTables.any(data.errors.containsKey)) {
        throw StateError('Required data is unavailable. Refresh and retry.');
      }
      final lots = {for (final l in data.lots) l['lot_id'].toString(): l};
      final List<List<Object?>> rows;
      switch (_report) {
        case 'Burial records':
          rows = [
            [
              'ID',
              'Deceased',
              'Lot',
              'Birth date',
              'Death date',
              'Burial date',
              'Interment date',
            ],
            ...data.burials
                .where(
                  (r) => _included(r['interment_date'] ?? r['burial_date']),
                )
                .map(
                  (r) => [
                    r['burial_id'],
                    r['name_of_deceased'],
                    lotReference(lots[r['lot_id'].toString()] ?? {}),
                    r['birth_date'],
                    r['death_date'],
                    r['burial_date'],
                    r['interment_date'],
                  ],
                ),
          ];
        case 'Visitor logs':
          rows = [
            ['ID', 'Visitor ID', 'Burial ID', 'Time in', 'Time out', 'Method'],
            ...data.visitors
                .where((r) => _included(r['time_in']))
                .map(
                  (r) => [
                    r['log_id'],
                    r['user_id'],
                    r['burial_id'],
                    r['time_in'],
                    r['time_out'],
                    r['method'],
                  ],
                ),
          ];
        case 'Visitor trends':
          rows = [
            ['Period start (Asia/Manila)', 'Interval', 'Entries'],
            ..._trend.entries.map(
              (e) => [
                DateFormat('yyyy-MM-dd').format(e.key),
                _interval.name,
                e.value,
              ],
            ),
          ];
        case 'Lot inventory':
          rows = [
            ['ID', 'Lot', 'Block', 'Status', 'Listed price'],
            ...data.lots.map(
              (r) => [
                r['lot_id'],
                lotReference(r),
                blockOf(r),
                r['status'],
                r['price'],
              ],
            ),
          ];
        case 'Lot sales':
          rows = [
            [
              'Ownership ID',
              'Lot',
              'Owner ID',
              'Start date',
              'Status',
              'Current listed lot price (not historical sale value)',
            ],
            ...data.sales
                .where((r) => _included(r['start_date']))
                .map(
                  (r) => [
                    r['ownership_id'],
                    lotReference(lots[r['lot_id'].toString()] ?? {}),
                    r['user_id'],
                    r['start_date'],
                    r['status'],
                    lots[r['lot_id'].toString()]?['price'],
                  ],
                ),
          ];
        case 'Payments':
          rows = [
            [
              'Transaction ID',
              'Ownership ID',
              'Amount',
              'Payment date',
              'Notes',
            ],
            ...data.payments
                .where((r) => _included(r['payment_date']))
                .map(
                  (r) => [
                    r['transaction_id'],
                    r['ownership_id'],
                    r['amount'],
                    r['payment_date'],
                    r['notes'],
                  ],
                ),
          ];
        case 'Lot demand':
          rows = [
            [
              'Block',
              'Lots',
              'Occupied',
              'Available',
              'Sold',
              'Used or sold',
              'Uptake %',
              'Demand',
              'Medium cutoff %',
              'High cutoff %',
            ],
            ..._demand.map(
              (d) => [
                d.block,
                d.lots,
                d.occupied,
                d.available,
                d.sold,
                d.usedOrSold,
                d.score.toStringAsFixed(2),
                d.level(medium: _medium, high: _high),
                _medium,
                _high,
              ],
            ),
          ];
        default:
          rows = [
            [
              'Burial ID',
              'Lot ID',
              'Block',
              'Latitude',
              'Longitude',
              'Cluster (noise = -1)',
              'Radius metres',
              'MinPts',
              'Excluded missing locations',
            ],
            for (var i = 0; i < _spatial.points.length; i++)
              [
                _spatial.points[i].id,
                _spatial.points[i].lotId,
                _spatial.points[i].block,
                _spatial.points[i].lat,
                _spatial.points[i].lng,
                _spatial.labels[i] < 0 ? -1 : _spatial.labels[i] + 1,
                _epsilon,
                _minPoints,
                _spatial.excluded,
              ],
          ];
      }
      final name =
          '${_report.toLowerCase().replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      await downloadCsv(encodeCsv(rows), name);
      await AuditService.log(
        action: 'EXPORT_REPORT',
        entityType: 'report',
        details:
            '$_report: ${rows.length - 1} rows; dates ${_range?.start} to ${_range?.end}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${rows.length - 1} rows.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
