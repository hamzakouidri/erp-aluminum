import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class MapPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const MapPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController _mapController = MapController();
  LatLng _selectedPoint = const LatLng(36.7538, 3.0588); // Default centered on Algiers
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<dynamic> _searchResults = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPoint = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=5',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'erp_aluminum_app'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _searchResults = data;
        });
      }
    } catch (e) {
      debugPrint('Error searching places: $e');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('تحديد الموقع على الخريطة', lang)),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, size: 28),
            onPressed: () {
              Navigator.pop(context, _selectedPoint);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPoint,
              initialZoom: 14.0,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedPoint = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                userAgentPackageName: 'erp_aluminum_app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedPoint,
                    width: 50.0,
                    height: 50.0,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 45.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Search box & search results overlay
          Positioned(
            top: 15,
            left: 15,
            right: 15,
            child: Column(
              children: [
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: Localization.translate('بحث عن مكان...', lang),
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.search, color: Colors.blue),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchResults = [];
                            });
                          },
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: (value) => _searchPlaces(value),
                    ),
                  ),
                ),
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Material(
                      elevation: 4,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
                if (_searchResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        color: Colors.white,
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final place = _searchResults[index];
                            return ListTile(
                              title: Text(
                                place['display_name'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black, fontSize: 13),
                              ),
                              onTap: () {
                                final lat = double.tryParse(place['lat'].toString());
                                final lon = double.tryParse(place['lon'].toString());
                                if (lat != null && lon != null) {
                                  final newPoint = LatLng(lat, lon);
                                  setState(() {
                                    _selectedPoint = newPoint;
                                    _searchResults = [];
                                    _searchController.text = place['display_name'];
                                  });
                                  _mapController.move(newPoint, 15.0);
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Helper tip bottom overlay
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Material(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  child: Text(
                    Localization.translate(
                      'اضغط على أي مكان في الخريطة لتحديد الموقع بدقة، ثم اضغط على زر الصح بالأعلى للحفظ',
                      lang,
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
