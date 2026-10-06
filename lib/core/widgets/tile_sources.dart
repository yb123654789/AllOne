/// 底图瓦片源。
///
/// **为什么需要可选**：OSM 官方瓦片（`tile.openstreetmap.org`）在国内常被
/// DNS 污染 / 直连超时，导致地图整块空白。实测本机：
/// - `tile.openstreetmap.org` / `basemaps.cartocdn.com` / `opentopomap.org` → 超时
/// - `server.arcgisonline.com`（Esri） → 正常
/// - `webrd01.is.autonavi.com`（高德）、`rt0.map.gtimg.com`（腾讯） → 正常
///
/// 因此默认用 Esri（官方允许直接使用），并把其它可用源做成可切换项。
class TileSource {
  final String id;
  final String name;

  /// URL 模板：`{z}/{x}/{y}`
  final String urlTemplate;

  /// 子域列表（部分源需要）；为空表示不需要
  final List<String> subdomains;

  /// 版权标注（供界面展示）
  final String attribution;

  /// 是否需要说明坐标偏移（高德/腾讯在国内用 GCJ-02，与 GPS 的 WGS-84 有偏移）
  final bool gcj02;

  const TileSource({
    required this.id,
    required this.name,
    required this.urlTemplate,
    this.subdomains = const [],
    this.attribution = '',
    this.gcj02 = false,
  });
}

/// 内置瓦片源
class TileSources {
  TileSources._();

  /// Esri 世界街道图。
  ///
  /// 官方服务，允许在应用中使用（**请求时请保留版权标注**）。
  /// URL 顺序与 OSM 不同：Esri 是 `/{z}/{y}/{x}`。
  static const esri = TileSource(
    id: 'esri',
    name: 'Esri 街道图（推荐）',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Street_Map/MapServer/tile/{z}/{y}/{x}',
    attribution: '© Esri',
  );

  /// Esri 卫星影像
  static const esriSatellite = TileSource(
    id: 'esri_sat',
    name: 'Esri 卫星影像',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: '© Esri',
  );

  /// OpenStreetMap 官方（部分地区直连不通）
  static const osm = TileSource(
    id: 'osm',
    name: 'OpenStreetMap（部分地区连不上）',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
  );

  /// 高德地图（国内快，但使用 GCJ-02 坐标，与 GPS 有偏移）
  static const amap = TileSource(
    id: 'amap',
    name: '高德地图（国内快；坐标有偏移）',
    urlTemplate:
        'https://webrd0{s}.is.autonavi.com/appmaptile'
        '?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
    subdomains: ['1', '2', '3', '4'],
    attribution: '© 高德地图',
    gcj02: true,
  );

  /// 腾讯地图（同上，GCJ-02）
  static const tencent = TileSource(
    id: 'tencent',
    name: '腾讯地图（国内快；坐标有偏移）',
    urlTemplate: 'https://rt{s}.map.gtimg.com/tile?z={z}&x={x}&y={y}&type=vector&styleid=3',
    subdomains: ['0', '1', '2', '3'],
    attribution: '© 腾讯地图',
    gcj02: true,
  );

  /// 全部内置源（界面按此顺序展示）
  static const all = <TileSource>[esri, esriSatellite, amap, tencent, osm];

  /// 默认源
  static const fallback = esri;

  /// 按 id 查源；找不到返回 [fallback]
  static TileSource byId(String? id) {
    if (id == null) return fallback;
    for (final s in all) {
      if (s.id == id) return s;
    }
    return fallback;
  }
}
