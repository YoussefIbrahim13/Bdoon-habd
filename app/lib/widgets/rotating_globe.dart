import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A dotted-wireframe holographic Earth, drawn entirely in code (no image
/// assets, no packages) in the NovaPay violet + neon-cyan palette.
///
/// Two layers spin together around the polar axis on a true orthographic
/// projection, with back-hemisphere culling so it reads as a solid sphere:
///   1. a cyan/lavender graticule (parallels + meridians),
///   2. violet continent outlines.
///
/// All geometry is projected onto the unit sphere ONCE at first use (see
/// [_geometry]) and shared by every instance; per frame the painter only
/// rotates cached unit vectors and batches the results into a handful of
/// `drawPoints` calls, so the cost is a few thousand multiplies inside a
/// [RepaintBoundary] — no path building, no `saveLayer`.
///
/// Meant to live UNDER a headline in a Stack: the center carries a dark veil
/// so overlaid text stays fully legible.
class RotatingGlobe extends StatefulWidget {
  final double size;

  /// Seconds for one full revolution.
  final double periodSeconds;

  const RotatingGlobe({super.key, this.size = 260, this.periodSeconds = 24});

  @override
  State<RotatingGlobe> createState() => _RotatingGlobeState();
}

class _RotatingGlobeState extends State<RotatingGlobe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (widget.periodSeconds * 1000).round()),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _GlobePainter(phase: _spin.value * 2 * math.pi),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Geometry (built once, shared)
// ---------------------------------------------------------------------------

/// Axial tilt, radians. Tips the north pole toward the viewer so the
/// graticule reads as a sphere rather than a flat set of vertical arcs.
const double _tilt = 20 * math.pi / 180;

/// Coarse landmass rings as flat `[lon, lat, lon, lat, …]` degree pairs,
/// each implicitly closed. Deliberately low-poly: the outlines are densified
/// and re-projected per frame, so a handful of vertices is enough to read as
/// the real continents.
const List<List<double>> _landRings = [
  // North + Central America
  [
    -168, 65, -160, 71, -140, 70, -125, 70, -110, 68, -95, 68, -82, 73, //
    -75, 68, -65, 60, -55, 52, -60, 45, -70, 42, -75, 35, -81, 25, //
    -84, 22, -88, 21, -92, 15, -85, 10, -78, 8, -86, 14, -95, 16, //
    -105, 20, -110, 24, -114, 31, -122, 37, -125, 48, -135, 58, //
    -150, 59, -165, 55,
  ],
  // South America
  [
    -78, 8, -72, 12, -62, 11, -52, 5, -45, -2, -35, -6, -38, -13, //
    -48, -25, -58, -34, -62, -42, -68, -52, -75, -52, -72, -42, //
    -71, -30, -70, -18, -77, -8, -80, 0,
  ],
  // Africa — Atlantic coast up through Morocco, then the Mediterranean rim
  // (Tunisia reaches 37N), down the Red Sea, round the Horn and the Cape.
  [
    -17, 15, -16, 21, -13, 28, -10, 31, -6, 36, 0, 36, 10, 37, 15, 32, //
    20, 31, 25, 32, 32, 31, 34, 28, 37, 22, 39, 15, 43, 12, 51, 12, //
    42, -2, 40, -15, 35, -24, 25, -34, 18, -34, 13, -23, 9, -1, 9, 4, //
    3, 6, -8, 5, -13, 9,
  ],
  // Eurasia
  [
    -10, 43, -9, 38, -6, 36, 3, 40, 10, 44, 16, 41, 19, 40, 24, 38, //
    27, 41, 30, 40, 35, 36, 36, 31, 35, 28, 43, 13, 52, 17, 57, 25, //
    50, 30, 60, 25, 67, 25, 70, 22, 73, 16, 77, 8, 80, 13, 84, 19, //
    87, 21, 92, 22, //
    97, 17, 99, 10, 104, 2, 107, 11, 109, 18, 117, 24, 122, 31, //
    122, 40, 128, 42, 130, 48, 135, 55, 143, 59, 150, 60, 160, 60, //
    170, 66, 179, 68, 170, 71, 160, 72, 140, 73, 120, 73, 105, 77, //
    90, 76, 75, 73, 60, 70, 45, 68, 30, 70, 20, 70, 10, 63, 5, 58, //
    0, 53, -5, 48,
  ],
  // Australia
  [
    114, -22, 122, -18, 130, -12, 137, -12, 142, -11, 146, -19, //
    150, -25, 153, -28, 150, -37, 143, -39, 135, -35, 129, -32, //
    120, -34, 115, -34, 113, -26,
  ],
  // Greenland
  [
    -45, 60, -30, 68, -22, 70, -20, 76, -30, 82, -45, 83, -58, 82, //
    -70, 78, -55, 68, -50, 62,
  ],
  // Madagascar
  [43, -12, 50, -15, 48, -25, 44, -22],
  // Great Britain
  [-5, 50, 1, 51, 2, 53, 0, 54, -2, 57, -3, 58, -5, 57, -3, 55, -3, 53, //
    -5, 52],
  // Ireland
  [-10, 52, -6, 52, -6, 55, -8, 55, -10, 54],
  // Japan
  [130, 31, 136, 34, 142, 40, 145, 44, 143, 44, 139, 37, 133, 33],
  // New Zealand
  [166, -46, 174, -41, 178, -38, 175, -40, 170, -44, 168, -46],
  // Antarctica — traced eastward from the antimeridian; the closing edge
  // wraps across ±180 (see [_densifyRing]). The spur near -60 is the
  // Antarctic Peninsula, traced up its west side and back down its east.
  [
    -180, -78, -165, -77, -150, -75, -135, -74, -120, -73, -105, -73, //
    -90, -72, -80, -71, -72, -70, -66, -67, -61, -64, -57, -63, //
    -59, -66, -62, -71, -50, -77, -38, -78, -28, -76, -18, -73, //
    -8, -70, 2, -69, 14, -70, 28, -70, 40, -68, 52, -66, 65, -67, //
    78, -67, 90, -66, 102, -66, 114, -66, 126, -66, 138, -66, //
    148, -68, 158, -71, 168, -75, 176, -78,
  ],
];

/// Everything the painter needs, in unit-sphere coordinates. `xyz` buffers
/// are flat triples so the per-frame rotation is a tight indexed loop with no
/// allocation or trigonometry per point.
class _Geometry {
  /// Continent outlines, one densified polyline each.
  final List<Float32List> outlines;

  /// Latitude rings.
  final List<Float32List> parallels;

  /// Longitude arcs.
  final List<Float32List> meridians;

  const _Geometry({
    required this.outlines,
    required this.parallels,
    required this.meridians,
  });
}

/// Lazily built on first paint, then reused by every [RotatingGlobe].
final _Geometry _geometry = _buildGeometry();

void _writeUnit(Float32List out, int i, double lonDeg, double latDeg) {
  final lon = lonDeg * math.pi / 180;
  final lat = latDeg * math.pi / 180;
  final cosLat = math.cos(lat);
  out[i] = cosLat * math.sin(lon);
  out[i + 1] = math.sin(lat);
  out[i + 2] = cosLat * math.cos(lon);
}

/// Subdivides a closed ring so no edge spans more than [maxStep] degrees —
/// straight screen-space segments between distant vertices would cut across
/// the sphere instead of wrapping around it.
///
/// Longitude steps take the short way around, so an edge that straddles the
/// antimeridian (Antarctica's closing segment) wraps across ±180 instead of
/// sweeping all the way back through Greenwich.
Float32List _densifyRing(List<double> ring, {double maxStep = 3}) {
  final pts = <double>[];
  final n = ring.length ~/ 2;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final x0 = ring[i * 2], y0 = ring[i * 2 + 1];
    final x1 = ring[j * 2], y1 = ring[j * 2 + 1];
    var dx = x1 - x0;
    if (dx > 180) dx -= 360;
    if (dx < -180) dx += 360;
    final dy = y1 - y0;
    final steps =
        math.max(1, (math.max(dx.abs(), dy.abs()) / maxStep).ceil());
    for (var s = 0; s < steps; s++) {
      final t = s / steps;
      pts..add(x0 + dx * t)..add(y0 + dy * t);
    }
  }
  // Close the loop.
  pts..add(ring[0])..add(ring[1]);

  final out = Float32List(pts.length ~/ 2 * 3);
  for (var i = 0; i < pts.length ~/ 2; i++) {
    _writeUnit(out, i * 3, pts[i * 2], pts[i * 2 + 1]);
  }
  return out;
}

Float32List _arc(
  double from,
  double to,
  double step,
  double Function(double) lonOf,
  double Function(double) latOf,
) {
  final count = ((to - from) / step).round() + 1;
  final out = Float32List(count * 3);
  for (var i = 0; i < count; i++) {
    final v = from + step * i;
    _writeUnit(out, i * 3, lonOf(v), latOf(v));
  }
  return out;
}

_Geometry _buildGeometry() {
  return _Geometry(
    outlines: [for (final ring in _landRings) _densifyRing(ring)],
    parallels: [
      for (final lat in const [-60.0, -30.0, 0.0, 30.0, 60.0])
        _arc(-180, 180, 4, (v) => v, (_) => lat),
    ],
    meridians: [
      for (var lon = -180.0; lon < 180.0; lon += 30)
        _arc(-88, 88, 4, (_) => lon, (v) => v),
    ],
  );
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

/// Depth bands. Segments are bucketed by how far they face the viewer, then
/// each bucket is drawn in one batched call — this is what keeps the frame
/// down to a handful of draw calls instead of a few thousand.
const List<double> _wireAlphaGrid = [0.09, 0.17, 0.26];
const List<double> _wireAlphaLand = [0.28, 0.55, 0.88];

int _band(double z) => z < 0.32 ? 0 : (z < 0.68 ? 1 : 2);

class _GlobePainter extends CustomPainter {
  final double phase;

  const _GlobePainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.78; // leave room for the glow halo
    final g = _geometry;

    _paintAtmosphere(canvas, center, r);
    _paintSphere(canvas, center, r);

    final cosP = math.cos(phase), sinP = math.sin(phase);
    final cosT = math.cos(_tilt), sinT = math.sin(_tilt);

    // Rotate about the polar axis, then tilt about X. Returns screen position
    // in [outPos]/[outY] via the closure-free triple below.
    late double px, py, pz;
    void project(Float32List src, int i) {
      final x0 = src[i], y0 = src[i + 1], z0 = src[i + 2];
      final x = x0 * cosP + z0 * sinP;
      final z = -x0 * sinP + z0 * cosP;
      final y = y0 * cosT - z * sinT;
      pz = y0 * sinT + z * cosT;
      px = center.dx + x * r;
      py = center.dy - y * r;
    }

    // --- Wireframe graticule + continent outlines -------------------------
    List<List<Offset>> emptyBands() => [<Offset>[], <Offset>[], <Offset>[]];
    final parallelBands = emptyBands();
    final meridianBands = emptyBands();
    final outlineBands = emptyBands();

    void addPolyline(Float32List line, List<List<Offset>> bands) {
      Offset? prev;
      var prevZ = -1.0;
      for (var i = 0; i < line.length; i += 3) {
        project(line, i);
        final here = Offset(px, py);
        final z = pz;
        if (z > 0 && prevZ > 0 && prev != null) {
          bands[_band((z + prevZ) / 2)]..add(prev)..add(here);
        }
        prev = here;
        prevZ = z;
      }
    }

    for (final line in g.parallels) {
      addPolyline(line, parallelBands);
    }
    for (final line in g.meridians) {
      addPolyline(line, meridianBands);
    }
    for (final line in g.outlines) {
      addPolyline(line, outlineBands);
    }

    void strokeBands(
      List<List<Offset>> bands,
      Color color,
      List<double> alphas,
      double width,
    ) {
      for (var b = 0; b < 3; b++) {
        if (bands[b].isEmpty) continue;
        canvas.drawPoints(
          ui.PointMode.lines,
          bands[b],
          Paint()
            ..color = color.withValues(alpha: alphas[b])
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    strokeBands(parallelBands, AppColors.electricBlue, _wireAlphaGrid, 1.0);
    strokeBands(meridianBands, AppColors.accentGlow, _wireAlphaGrid, 1.0);
    strokeBands(outlineBands, AppColors.primaryViolet, _wireAlphaLand, 1.2);

    _paintTextVeil(canvas, center, r);
    _paintRim(canvas, center, r);
  }

  /// Outer cyan/violet halo bleeding off the sphere.
  void _paintAtmosphere(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center,
      r * 1.3,
      Paint()
        ..shader = ui.Gradient.radial(center, r * 1.3, [
          AppColors.accentGlow.withValues(alpha: 0),
          AppColors.accentGlow.withValues(alpha: .07),
          AppColors.electricBlue.withValues(alpha: .18),
          AppColors.electricBlue.withValues(alpha: 0),
        ], const [
          0.0,
          0.62,
          0.78,
          1.0,
        ]),
    );
  }

  /// Deep violet base sphere, lit from the upper left.
  void _paintSphere(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(center.dx - r * .32, center.dy - r * .34),
          r * 1.55,
          [AppColors.surface, AppColors.bg, const Color(0xFF060410)],
          const [0.0, 0.55, 1.0],
        ),
    );
  }

  /// Keeps "بدون هبد!" at full contrast: the wireframe is darkened toward the
  /// middle of the disc, where the headline sits, and left bright at the limb.
  void _paintTextVeil(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(center, r, [
          AppColors.bg.withValues(alpha: .72),
          AppColors.bg.withValues(alpha: .46),
          AppColors.bg.withValues(alpha: 0),
        ], const [
          0.0,
          0.42,
          0.9,
        ]),
    );
  }

  /// Crisp holographic rim: a bright cyan-to-violet edge plus a soft bloom.
  void _paintRim(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..color = AppColors.electricBlue.withValues(alpha: .3),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(
          Offset(center.dx - r, center.dy - r),
          Offset(center.dx + r, center.dy + r),
          [
            AppColors.electricBlue.withValues(alpha: .75),
            AppColors.accentGlow.withValues(alpha: .45),
            AppColors.displayViolet.withValues(alpha: .12),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_GlobePainter old) => old.phase != phase;
}
