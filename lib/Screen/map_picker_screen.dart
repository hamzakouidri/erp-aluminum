import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class MapPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? clientName;
  final String? title;

  const MapPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.clientName,
    this.title,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController _mapController = MapController();
  LatLng _selectedPoint = const LatLng(36.7538, 3.0588); // Default: Algiers
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounceTimer;
  Timer? _reverseGeocodeTimer;
  bool _isSatellite = false;
  bool _isLocating = false;
  bool _isResolvingAddress = false;
  bool _hasCompletedSearch = false;
  String? _selectedAddress;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPoint = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _reverseGeocodeTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _hasCompletedSearch = false;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasCompletedSearch = false;
    });

    final results = <Map<String, dynamic>>[];
    final searchCenter = _selectedPoint;
    final latitudeSpan = 1.25;
    final longitudeSpan =
        1.25 / math.cos(searchCenter.latitude * math.pi / 180).abs().clamp(0.25, 1.0);
    final viewbox = [
      searchCenter.longitude - longitudeSpan,
      searchCenter.latitude + latitudeSpan,
      searchCenter.longitude + longitudeSpan,
      searchCenter.latitude - latitudeSpan,
    ].join(',');

    double distanceFromSearchCenter(double lat, double lon) {
      final dLat = (lat - searchCenter.latitude) * 111.0;
      final dLon =
          (lon - searchCenter.longitude) *
          111.0 *
          math.cos(searchCenter.latitude * math.pi / 180);
      return math.sqrt(dLat * dLat + dLon * dLon);
    }

    void addResult({required String name, required double lat, required double lon}) {
      if (results.any((item) =>
          (item['lat'] as double).toStringAsFixed(5) == lat.toStringAsFixed(5) &&
          (item['lon'] as double).toStringAsFixed(5) == lon.toStringAsFixed(5))) {
        return;
      }
      results.add({
        'name': name,
        'lat': lat,
        'lon': lon,
        'distanceKm': distanceFromSearchCenter(lat, lon),
      });
    }

    try {
      // Restrict results to Algeria and bias them toward the current map area.
      // This gives Google-like nearby suggestions without returning worldwide
      // matches for common street/city names.
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json'
        '&q=${Uri.encodeComponent(cleanQuery)}'
        '&countrycodes=dz&viewbox=$viewbox&bounded=0&limit=8'
        '&addressdetails=1&accept-language=ar,fr',
      );
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'ERPAluminumApp/1.0 (contact: info@erpalum.com)',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          for (final item in data) {
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lon = double.tryParse(item['lon']?.toString() ?? '');
            if (lat != null && lon != null) {
              addResult(
                name: item['display_name'] ?? item['name'] ?? '',
                lat: lat,
                lon: lon,
              );
            }
          }
        }
      }
    } catch (_) {
      // Fallback to Photon geocoding if Nominatim fails or times out
      try {
        final photonUrl = Uri.parse(
          'https://photon.komoot.io/api/?q=${Uri.encodeComponent(cleanQuery)}'
          '&limit=8&lang=fr&bbox=${searchCenter.longitude - longitudeSpan},'
          '${searchCenter.latitude - latitudeSpan},${searchCenter.longitude + longitudeSpan},'
          '${searchCenter.latitude + latitudeSpan}',
        );
        final response = await http.get(photonUrl).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final features = data['features'];
          if (features is List) {
            for (final f in features) {
              final props = f['properties'] as Map<String, dynamic>?;
              final geom = f['geometry'] as Map<String, dynamic>?;
              final coords = geom?['coordinates'] as List?;
              if (props != null && coords != null && coords.length >= 2) {
                final lon = (coords[0] as num).toDouble();
                final lat = (coords[1] as num).toDouble();
                final parts = <String>[
                  props['name']?.toString() ?? '',
                  props['city']?.toString() ?? props['district']?.toString() ?? '',
                  props['state']?.toString() ?? '',
                  props['country']?.toString() ?? '',
                ].where((s) => s.isNotEmpty).toList();
                final country = props['country']?.toString().toLowerCase() ?? '';
                if (country.contains('alger') || country.contains('الجزائر')) {
                  addResult(name: parts.join('، '), lat: lat, lon: lon);
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      results.sort(
        (a, b) => (a['distanceKm'] as double).compareTo(b['distanceKm'] as double),
      );
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _hasCompletedSearch = true;
      });
    }
  }

  void _selectPoint(LatLng point, {String? knownAddress, double? zoom}) {
    setState(() {
      _selectedPoint = point;
      _selectedAddress = knownAddress;
      _searchResults = [];
      _hasCompletedSearch = false;
    });
    if (zoom != null) _mapController.move(point, zoom);
    if (knownAddress == null || knownAddress.trim().isEmpty) {
      _scheduleReverseGeocode(point);
    }
  }

  void _scheduleReverseGeocode(LatLng point) {
    _reverseGeocodeTimer?.cancel();
    _reverseGeocodeTimer = Timer(
      const Duration(milliseconds: 350),
      () => _reverseGeocode(point),
    );
  }

  Future<void> _reverseGeocode(LatLng point) async {
    if (!mounted) return;
    setState(() => _isResolvingAddress = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
        '&lat=${point.latitude}&lon=${point.longitude}'
        '&zoom=18&addressdetails=1&accept-language=ar,fr',
      );
      final response = await http.get(
        url,
        headers: const {
          'User-Agent': 'ERPAluminumApp/1.0 (contact: info@erpalum.com)',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final data = json.decode(response.body);
      final address = data is Map ? data['display_name']?.toString().trim() : null;
      if (!mounted || address == null || address.isEmpty) return;
      if ((_selectedPoint.latitude - point.latitude).abs() > 0.000001 ||
          (_selectedPoint.longitude - point.longitude).abs() > 0.000001) {
        return;
      }
      setState(() => _selectedAddress = address);
    } catch (_) {
      // Coordinates remain usable when the address service is offline.
    } finally {
      if (mounted) setState(() => _isResolvingAddress = false);
    }
  }

  void _changeZoom(double delta) {
    final camera = _mapController.camera;
    final nextZoom = (camera.zoom + delta).clamp(3.0, 20.0).toDouble();
    _mapController.move(camera.center, nextZoom);
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('خدمة تحديد الموقع (GPS) غير مفعلة في جهازك')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم رفض إذن الوصول إلى الموقع')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('إذن الموقع محظور بشكل دائم، يرجى تفعيله من إعدادات الهاتف')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final newPoint = LatLng(position.latitude, position.longitude);
      _selectPoint(newPoint, zoom: 17.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر جلب موقعك الحالي: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;

    // Google Maps tile templates:
    // lyrs=m : Normal Google Maps Roadmap
    // lyrs=y : Google Hybrid (Satellite + Roads & Names)
    final googleTileUrl = _isSatellite
        ? 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
        : 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';

    final screenTitle = widget.title ??
        (widget.clientName != null && widget.clientName!.trim().isNotEmpty
            ? '${Localization.translate('تحديد موقع:', lang)} ${widget.clientName}'
            : Localization.translate('خرائط جوجل - تحديد موقع العميل', lang));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          screenTitle,
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          // Switch between Normal and Satellite view
          IconButton(
            tooltip: _isSatellite ? 'الخريطة العادية' : 'القمر الصناعي',
            icon: Icon(_isSatellite ? Icons.map_outlined : Icons.satellite_alt_rounded),
            onPressed: () {
              setState(() {
                _isSatellite = !_isSatellite;
              });
            },
          ),
          // Open in Google Maps app / browser
          IconButton(
            tooltip: Localization.translate('فتح في تطبيق خرائط Google', lang),
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.amberAccent),
            onPressed: () async {
              final lat = _selectedPoint.latitude;
              final lng = _selectedPoint.longitude;
              final googleNav = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
              final googleWeb = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
              try {
                final opened = await launchUrl(googleNav, mode: LaunchMode.externalApplication);
                if (!opened) {
                  await launchUrl(googleWeb, mode: LaunchMode.externalApplication);
                }
              } catch (_) {
                await launchUrl(googleWeb, mode: LaunchMode.externalApplication);
              }
            },
          ),
          IconButton(
            tooltip: Localization.translate('تأكيد وحفظ', lang),
            icon: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
            onPressed: () {
              Navigator.pop(context, _selectedPoint);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Real Google Maps Layer via FlutterMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPoint,
              initialZoom: 15.0,
              maxZoom: 20.0,
              minZoom: 3.0,
              onTap: (tapPosition, point) {
                _selectPoint(point);
              },
              onLongPress: (tapPosition, point) => _selectPoint(point),
            ),
            children: [
              TileLayer(
                key: ValueKey('google_tiles_$_isSatellite'),
                urlTemplate: googleTileUrl,
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                userAgentPackageName: 'com.google.android.apps.maps',
                maxZoom: 20,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedPoint,
                    width: 60.0,
                    height: 60.0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Text(
                            'موقع العميل',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFFEA4335),
                          size: 40.0,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Working Google Maps Search Bar
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 6,
                  shadowColor: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: _isSearching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search_rounded, color: Colors.blue),
                          onPressed: () => _searchPlaces(_searchController.text),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.black, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: Localization.translate('ابحث عن مدينة، حي، أو شارع...', lang),
                              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: _onSearchChanged,
                            onSubmitted: _searchPlaces,
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                                _hasCompletedSearch = false;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),

                // Search Results Dropdown List
                if (_searchResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        color: Colors.white,
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final place = _searchResults[index];
                            return ListTile(
                              leading: const Icon(Icons.location_on_outlined, color: Colors.redAccent),
                              title: Text(
                                place['name'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black87, fontSize: 13),
                              ),
                              subtitle: place['distanceKm'] is double
                                  ? Text(
                                      '${(place['distanceKm'] as double).toStringAsFixed(1)} km',
                                      style: const TextStyle(fontSize: 11),
                                    )
                                  : null,
                              onTap: () {
                                final lat = place['lat'] as double;
                                final lon = place['lon'] as double;
                                final newPoint = LatLng(lat, lon);
                                _searchController.text = place['name'];
                                _selectPoint(
                                  newPoint,
                                  knownAddress: place['name']?.toString(),
                                  zoom: 16.5,
                                );
                                FocusScope.of(context).unfocus();
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                if (_hasCompletedSearch &&
                    !_isSearching &&
                    _searchResults.isEmpty &&
                    _searchController.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Material(
                      elevation: 5,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search_off_rounded, color: Colors.grey),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                Localization.translate('لا توجد نتائج مطابقة', lang),
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Positioned(
            right: 16,
            bottom: 154,
            child: Material(
              color: Colors.white,
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: Localization.translate('تكبير', lang),
                    onPressed: () => _changeZoom(1),
                    icon: const Icon(Icons.add, color: Colors.black87),
                  ),
                  const SizedBox(width: 42, child: Divider(height: 1)),
                  IconButton(
                    tooltip: Localization.translate('تصغير', lang),
                    onPressed: () => _changeZoom(-1),
                    icon: const Icon(Icons.remove, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),

          // GPS "Locate Me" Floating Button
          Positioned(
            right: 16,
            bottom: 250,
            child: FloatingActionButton.small(
              heroTag: 'locate_me_btn',
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue.shade800,
              elevation: 4,
              tooltip: 'موقعي الحالي',
              onPressed: _isLocating ? null : _getCurrentLocation,
              child: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
            ),
          ),

          // Bottom Confirmation Card
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop_rounded, color: Colors.red, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الإحداثيات المحددة:',
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${_selectedPoint.latitude.toStringAsFixed(6)}, ${_selectedPoint.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(context, _selectedPoint);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text(
                        'تأكيد الموقع',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
