import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/cloud_sync_service.dart';

class DistributionTrackingScreen extends StatefulWidget {
  const DistributionTrackingScreen({super.key});

  @override
  State<DistributionTrackingScreen> createState() => _DistributionTrackingScreenState();
}

class _DistributionTrackingScreenState extends State<DistributionTrackingScreen> with SingleTickerProviderStateMixin {
  final SqlDatabase _db = SqlDatabase();
  List<Map<String, dynamic>> _deliveries = [];
  bool _isLoading = true;
  Map<String, dynamic>? _selectedDelivery;
  bool _isSidebarOpen = true;

  // Live Tracking state
  bool _isTracking = false;
  bool _isSettingWorkshop = false;
  LatLng _launchPosition = const LatLng(36.7538, 3.0588); // Starting/Launch location
  LatLng _driverPosition = const LatLng(36.7538, 3.0588); // Start at workshop (Algiers)
  LatLng _clientPosition = const LatLng(36.7372, 3.0855); // Client location
  double _distanceRemaining = 5.2; // in km
  int _etaMinutes = 12;
  double _speedKmh = 0.0;
  
  // Telemetry details
  String _trackingSource = 'Phone GPS'; // Phone GPS vs OBD Device
  int _satellites = 12;
  double _batteryVoltage = 13.8;
  int _engineRpm = 1800;
  double _fuelRate = 6.4; // L/100km
  
  Timer? _simulationTimer;
  int _simulationStep = 0;
  List<LatLng> _routePoints = [];
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _gpsSubscription;

  @override
  void initState() {
    super.initState();
    _loadDeliveries();
    _loadWorkshopLocation();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _gpsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDeliveries() async {
    setState(() => _isLoading = true);
    try {
      final dbInstance = await _db.db;
      if (dbInstance != null) {
        // Resilient query using LEFT JOIN to guarantee records are shown even if IDs match partially
        final res = await dbInstance.rawQuery('''
          SELECT cd.*, c.firstname, c.lastname, c.phone1, c.address, c.latitude, c.longitude, com.total as order_total
          FROM Commandes_deliveries cd
          LEFT JOIN Client c ON cd.client_id = c.id
          LEFT JOIN Commandes com ON cd.id_commandes = com.id
          ORDER BY cd.delivery_date DESC
        ''');
        setState(() {
          _deliveries = res;
          _isLoading = false;
        });
        if (res.isNotEmpty) {
          _selectDelivery(res.first);
        } else {
          setState(() {
            _selectedDelivery = null;
          });
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading deliveries: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchRoadRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson'
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;
          
          List<LatLng> points = coordinates.map((coord) {
            final l = coord as List;
            return LatLng(l[1].toDouble(), l[0].toDouble());
          }).toList();

          double distanceKm = 0.0;
          int durationMin = 0;
          if (route['legs'] != null && route['legs'].isNotEmpty) {
            final leg = route['legs'][0];
            distanceKm = (leg['distance'] as num).toDouble() / 1000.0;
            durationMin = ((leg['duration'] as num).toDouble() / 60.0).round();
          }

          setState(() {
            _routePoints = points;
            _distanceRemaining = distanceKm;
            _etaMinutes = durationMin;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint("OSRM routing error: $e");
    }

    // Fallback: Generate straight-line path if API fails
    setState(() {
      _routePoints = _generateRoutePoints(start, end);
      _distanceRemaining = _calculateDistance(start, end);
      _etaMinutes = (_distanceRemaining / 0.5).round();
    });
  }

  void _selectDelivery(Map<String, dynamic> delivery) {
    setState(() {
      _selectedDelivery = delivery;
      double cLat = delivery['latitude'] != null ? double.tryParse(delivery['latitude'].toString()) ?? 36.7372 : 36.7372;
      double cLng = delivery['longitude'] != null ? double.tryParse(delivery['longitude'].toString()) ?? 3.0855 : 3.0855;
      _clientPosition = LatLng(cLat, cLng);
      _driverPosition = _launchPosition;
      _speedKmh = 0.0;
      _isTracking = false;
      _simulationTimer?.cancel();
    });

    _fetchRoadRoute(_launchPosition, _clientPosition);
    
    // Animate map camera to fit both launch position and client
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: [_launchPosition, _clientPosition],
          padding: const EdgeInsets.all(50.0),
        ),
      );
    });
  }

  List<LatLng> _generateRoutePoints(LatLng start, LatLng end) {
    List<LatLng> points = [];
    int segments = 20;
    for (int i = 0; i <= segments; i++) {
      double t = i / segments;
      double lat = start.latitude + (end.latitude - start.latitude) * t;
      double lng = start.longitude + (end.longitude - start.longitude) * t;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((p2.latitude - p1.latitude) * p)/2 + 
          c(p1.latitude * p) * c(p2.latitude * p) * 
          (1 - c((p2.longitude - p1.longitude) * p))/2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
  }

  Future<void> _loadWorkshopLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      double? lat = prefs.getDouble('workshop_latitude');
      double? lng = prefs.getDouble('workshop_longitude');
      if (lat != null && lng != null) {
        setState(() {
          _launchPosition = LatLng(lat, lng);
          _driverPosition = LatLng(lat, lng);
        });
      }
    } catch (e) {
      debugPrint("Error loading workshop location: $e");
    }
  }

  Future<void> _saveWorkshopLocation(LatLng point) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('workshop_latitude', point.latitude);
      await prefs.setDouble('workshop_longitude', point.longitude);
      setState(() {
        _launchPosition = point;
        _driverPosition = point;
      });
      await _fetchRoadRoute(_launchPosition, _clientPosition);
      final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('تم تعيين موقع الورشة الجديد بنجاح!', lang),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("Error saving workshop location: $e");
    }
  }

  Future<void> _updateClientLocation(LatLng point) async {
    if (_selectedDelivery == null || _selectedDelivery!['client_id'] == null) return;
    try {
      final dbInstance = await _db.db;
      if (dbInstance != null) {
        await dbInstance.rawUpdate('''
          UPDATE Client
          SET latitude = ?, longitude = ?
          WHERE id = ?
        ''', [point.latitude.toString(), point.longitude.toString(), _selectedDelivery!['client_id']]);
        
        final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate('تم تعيين موقع الزبون الجديد بنجاح!', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Refresh deliveries list to update local cached state
        await _loadDeliveries();
        
        // Fetch real road route
        await _fetchRoadRoute(_launchPosition, point);
      }
    } catch (e) {
      debugPrint("Error updating client location: $e");
    }
  }

  Future<void> _toggleGPSTracking() async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    if (_isTracking) {
      _gpsSubscription?.cancel();
      _gpsSubscription = null;
      setState(() {
        _isTracking = false;
        _speedKmh = 0.0;
      });
      return;
    }

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('الرجاء تفعيل خدمة الموقع GPS في الهاتف', lang),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate('تم رفض صلاحية الوصول للموقع الجغرافي', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('تم رفض صلاحيات الموقع بشكل دائم. يرجى تفعيلها من الإعدادات', lang),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isTracking = true;
    });

    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      LatLng currentPos = LatLng(position.latitude, position.longitude);
      setState(() {
        _driverPosition = currentPos;
        _speedKmh = position.speed * 3.6; // convert m/s to km/h
        _distanceRemaining = _calculateDistance(_driverPosition, _clientPosition);
        _etaMinutes = _speedKmh > 5 ? (_distanceRemaining / (_speedKmh / 60)).round() : (_distanceRemaining / 0.5).round();
      });

      // Update actual road route dynamically from current position to client position
      _fetchRoadRoute(currentPos, _clientPosition);

      _mapController.move(_driverPosition, _mapController.camera.zoom);

      // Check if driver has reached destination (within 50 meters)
      if (_distanceRemaining < 0.05) {
        _gpsSubscription?.cancel();
        _gpsSubscription = null;
        setState(() {
          _isTracking = false;
          _speedKmh = 0.0;
        });
        _showDeliveryFinishedDialog();
      }
    }, onError: (e) {
      debugPrint("GPS stream error: $e");
    });
  }

  void _showDeliveryFinishedDialog() {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 8),
            Text(
              Localization.translate('وصلت الشحنة', lang),
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          Localization.translate('لقد وصلت المركبة إلى موقع تسليم الزبون بنجاح.', lang),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(fontFamily: 'Cairo')),
          )
        ],
      ),
    );
  }

  void _callClient(String phone) async {
    final Uri url = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _markAsDelivered() async {
    if (_selectedDelivery == null) return;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    
    // Update main order status to Full Distribution or Partial Distribution
    final orderId = _selectedDelivery!['id_commandes'];
    await _db.updateCommandeStatus(orderId, 'Full Distribution');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Localization.translate('تم تحديث حالة التوزيع بنجاح!', lang)),
        backgroundColor: Colors.green,
      ),
    );
    _loadDeliveries();
  }

  void _showCreatePlanDialog() async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    
    // Load confirmed/paid/in-progress orders
    List<Map<String, dynamic>> allOrders = [];
    try {
      allOrders = await _db.readCommandesWithClients();
    } catch (e) {
      debugPrint("Error loading orders: $e");
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            Localization.translate('إنشاء خطة توزيع جديدة', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 600,
            child: CreatePlanDialogContent(
              orders: allOrders,
              db: _db,
              lang: lang,
              onSuccess: () {
                Navigator.pop(dialogContext);
                _loadDeliveries();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmResetInstallationData(BuildContext context, AppLanguage lang) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد المسح الكلي للتركيبات', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        content: const Text('هل أنت تأكد من تصفير ومسح جميع بيانات التركيبات والتحفظات الميدانية بالتطوير؟', style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح كلي 🧹', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await _db.db;
      if (db != null) {
        await db.rawUpdate('''
          UPDATE WorkerAllocations 
          SET is_transferred_to_dist = 0, transferred_at = NULL,
              is_distributed = 0, distributed_at = NULL,
              is_installed = 0, installed_at = NULL,
              is_completed = 0, completed_at = NULL,
              has_reserve = 0, reserve_notes = NULL, reserve_at = NULL
        ''');
      }
      CloudSyncService().notifyChange();
      await _loadDeliveries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم مسح وتصفير كافة بيانات التركيبات بنجاح 🧹'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isAr = lang == AppLanguage.arabic;

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('خطط التوزيع والتتبع المباشر', lang)),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _confirmResetInstallationData(context, lang),
            icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 18),
            label: const Text(
              'تصفير التركيبات 🧹',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              elevation: 0,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showCreatePlanDialog,
            icon: Icon(Icons.add, color: Theme.of(context).cardColor),
            label: Text(
              Localization.translate('خطة جديدة', lang),
              style: TextStyle(fontFamily: 'Cairo', color: Theme.of(context).cardColor),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue.shade700,
              elevation: 0,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDeliveries,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deliveries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 80, color: Colors.blue.shade200),
                      const SizedBox(height: 16),
                      Text(
                        Localization.translate('لا توجد خطط توزيع حالية', lang),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _showCreatePlanDialog,
                        icon: const Icon(Icons.add),
                        label: Text(
                          Localization.translate('إنشاء خطة توزيع جديدة', lang),
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    // Left list panel: Active distributions (collapsable)
                    if (_isSidebarOpen)
                      Container(
                        width: 320,
                        decoration: BoxDecoration(color: Theme.of(context).cardColor,
                          border: Border(
                            right: BorderSide(color: Theme.of(context).dividerColor, width: isAr ? 0 : 1),
                            left: BorderSide(color: Theme.of(context).dividerColor, width: isAr ? 1 : 0),
                          ),
                        ),
                        child: ListView.builder(
                          itemCount: _deliveries.length,
                          itemBuilder: (context, index) {
                            final del = _deliveries[index];
                            final isSelected = _selectedDelivery?['id'] == del['id'];
                            final clientName = del['firstname'] != null 
                                ? '${del['firstname']} ${del['lastname'] ?? ''}'
                                : 'Client #${del['client_id']}';
                            final dateStr = del['delivery_date']?.toString() ?? '';

                            return Container(
                              color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                              child: ListTile(
                                onTap: () => _selectDelivery(del),
                                title: Text(
                                  clientName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${Localization.translate('رقم الطلبية:', lang)} #${del['id_commandes']}',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      '${Localization.translate('تاريخ التوزيع:', lang)} $dateStr',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                                trailing: Icon(
                                  Icons.delivery_dining,
                                  color: isSelected ? Colors.blue : Colors.grey,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // Side panel collapse/expand tab handle
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSidebarOpen = !_isSidebarOpen;
                        });
                      },
                      child: Container(
                        width: 22,
                        height: 70,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade800,
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(isAr ? 0 : 8),
                            bottomRight: Radius.circular(isAr ? 0 : 8),
                            topLeft: Radius.circular(isAr ? 8 : 0),
                            bottomLeft: Radius.circular(isAr ? 8 : 0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: const Offset(1, 1),
                            )
                          ],
                        ),
                        child: Icon(
                          _isSidebarOpen 
                              ? (isAr ? Icons.chevron_right : Icons.chevron_left) 
                              : (isAr ? Icons.chevron_left : Icons.chevron_right),
                          color: Theme.of(context).cardColor,
                          size: 16,
                        ),
                      ),
                    ),
                    // Right panel: Map + Telemetry details
                    Expanded(
                      child: Column(
                        children: [
                          // Map Section
                          Expanded(
                            flex: 3,
                            child: Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter: _driverPosition,
                                    initialZoom: 14.0,
                                    onTap: (tapPosition, point) {
                                      if (_isSettingWorkshop) {
                                        _saveWorkshopLocation(point);
                                        setState(() {
                                          _isSettingWorkshop = false;
                                        });
                                      } else {
                                        _updateClientLocation(point);
                                      }
                                    },
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                                      userAgentPackageName: 'erp_aluminum_app',
                                    ),
                                    PolylineLayer(
                                      polylines: [
                                        Polyline(
                                          points: _routePoints,
                                          color: Colors.blue.shade600,
                                          strokeWidth: 4.5,
                                        ),
                                      ],
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        // Starting / Launch Point
                                        Marker(
                                          point: _launchPosition,
                                          width: 100,
                                          height: 70,
                                          alignment: Alignment.topCenter,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade800,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  Localization.translate('الانطلاق', lang),
                                                  style: TextStyle(
                                                    color: Theme.of(context).cardColor,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.location_on,
                                                color: Colors.green,
                                                size: 32,
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Client / Destination Location
                                        Marker(
                                          point: _clientPosition,
                                          width: 100,
                                          height: 70,
                                          alignment: Alignment.topCenter,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade800,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  Localization.translate('الزبون', lang),
                                                  style: TextStyle(
                                                    color: Theme.of(context).cardColor,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.location_on,
                                                color: Colors.red,
                                                size: 32,
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Driver / Vehicle location
                                        Marker(
                                          point: _driverPosition,
                                          width: 50,
                                          height: 50,
                                          child: Image.asset(
                                            'Icon/icon.png',
                                            width: 38,
                                            height: 38,
                                            errorBuilder: (_, __, ___) => CircleAvatar(
                                              backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue.shade800,
                                              child: Icon(
                                                Icons.local_shipping,
                                                color: Theme.of(context).cardColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                // Floating Workshop Settings Buttons
                                Positioned(
                                  top: 16,
                                  right: isAr ? 16 : null,
                                  left: isAr ? null : 16,
                                  child: Column(
                                    crossAxisAlignment: isAr ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                    children: [
                                      FloatingActionButton.small(
                                        heroTag: 'workshop_gps_btn',
                                        onPressed: () async {
                                          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                                          if (!serviceEnabled) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  Localization.translate('الرجاء تفعيل خدمة الموقع GPS في الهاتف', lang),
                                                  style: const TextStyle(fontFamily: 'Cairo'),
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                            return;
                                          }
                                          Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
                                          await _saveWorkshopLocation(LatLng(position.latitude, position.longitude));
                                        },
                                        backgroundColor: Colors.orange.shade800,
                                        foregroundColor: Theme.of(context).cardColor,
                                        tooltip: Localization.translate('تعيين موقع الورشة من الـ GPS الحالي', lang),
                                        child: const Icon(Icons.storefront),
                                      ),
                                      const SizedBox(height: 8),
                                      FloatingActionButton.small(
                                        heroTag: 'workshop_map_btn',
                                        onPressed: () {
                                          setState(() {
                                            _isSettingWorkshop = !_isSettingWorkshop;
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                Localization.translate(
                                                  _isSettingWorkshop 
                                                      ? 'اضغط الآن على الخريطة لتحديد موقع الورشة' 
                                                      : 'تم الخروج من وضع تحديد موقع الورشة', 
                                                lang),
                                                style: const TextStyle(fontFamily: 'Cairo'),
                                              ),
                                              backgroundColor: _isSettingWorkshop ? Colors.orange : Colors.grey,
                                            ),
                                          );
                                        },
                                        backgroundColor: _isSettingWorkshop ? Colors.green : Colors.orange.shade300,
                                        foregroundColor: Theme.of(context).cardColor,
                                        tooltip: Localization.translate('تحديد موقع الورشة على الخريطة', lang),
                                        child: const Icon(Icons.add_location_alt),
                                      ),
                                    ],
                                  ),
                                ),
                                // Floating Speed and Distance Card
                                Positioned(
                                  top: 16,
                                  right: isAr ? null : 16,
                                  left: isAr ? 16 : null,
                                  child: Card(
                                    elevation: 6,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.speed, color: Colors.blue, size: 20),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${_speedKmh.toStringAsFixed(0)} ${Localization.translate('كم/سا', lang)}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.navigation, color: Colors.green, size: 20),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${_distanceRemaining.toStringAsFixed(1)} ${Localization.translate('كم متبقي', lang)}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.timer, color: Colors.orange, size: 20),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${Localization.translate('الوصول المتوقع:', lang)} $_etaMinutes ${Localization.translate('دقيقة', lang)}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Driver Actions and Simulated GPS Panel
                          Container(
                            height: 240,
                            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor,
                              border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
                            ),
                            child: _selectedDelivery == null
                                ? Center(
                                    child: Text(
                                      Localization.translate('اختر خطة توزيع لعرض التفاصيل', lang),
                                      style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 13),
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Row 1: Title and Actions
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${Localization.translate('تفاصيل التوصيل', lang)} (${_selectedDelivery!['firstname'] ?? ''} ${_selectedDelivery!['lastname'] ?? ''})',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  fontFamily: 'Cairo',
                                                  color: Colors.blue,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 4,
                                              children: [
                                                if (_selectedDelivery!['phone1'] != null)
                                                  ElevatedButton.icon(
                                                    onPressed: () => _callClient(_selectedDelivery!['phone1']),
                                                    icon: const Icon(Icons.phone, size: 14),
                                                    label: Text(
                                                      Localization.translate('اتصال بالزبون', lang),
                                                      style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.green.shade700,
                                                      foregroundColor: Theme.of(context).cardColor,
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    ),
                                                  ),
                                                ElevatedButton.icon(
                                                  onPressed: _markAsDelivered,
                                                  icon: const Icon(Icons.check_circle_outline, size: 14),
                                                  label: Text(
                                                    Localization.translate('توزيع تام / تسليم ناجح', lang),
                                                    style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue.shade800,
                                                    foregroundColor: Theme.of(context).cardColor,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Row 2: Customer Address and Phone
                                        Text(
                                          '${Localization.translate('الهاتف:', lang)} ${_selectedDelivery!['phone1'] ?? 'Non Spécifié'} | ${Localization.translate('العنوان:', lang)} ${_selectedDelivery!['address'] ?? 'Non Spécifié'}',
                                          style: TextStyle(fontSize: 12, fontFamily: 'Cairo'),
                                        ),
                                        const Divider(height: 16),
                                        // Row 3: Vehicle & GPS Telemetry Card
                                        Card(
                                          color: Colors.grey.shade50,
                                          elevation: 0,
                                          margin: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            side: BorderSide(color: Theme.of(context).dividerColor),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(10.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(
                                                      Localization.translate('موقع السائق وحالة الـ GPS', lang),
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'),
                                                    ),
                                                    Text(
                                                      _isTracking ? 'تتبع نشط 🟢' : 'غير متصل 🔴',
                                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text('${Localization.translate('خط العرض:', lang)} ${_driverPosition.latitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                                                          const SizedBox(height: 4),
                                                          Text('${Localization.translate('خط الطول:', lang)} ${_driverPosition.longitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                                                        ],
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text('${Localization.translate('السرعة الحالية:', lang)} ${_speedKmh.toStringAsFixed(1)} كم/سا', style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                                                          const SizedBox(height: 4),
                                                          Text('${Localization.translate('المسافة المتبقية:', lang)} ${_distanceRemaining.toStringAsFixed(2)} كم', style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                                                        ],
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 170,
                                                      height: 32,
                                                      child: ElevatedButton.icon(
                                                        onPressed: _toggleGPSTracking,
                                                        icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow, size: 16),
                                                        label: Text(
                                                          Localization.translate(_isTracking ? 'إيقاف التتبع' : 'بدء التتبع / المحاكاة', lang),
                                                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: _isTracking ? Colors.red : Colors.green,
                                                          foregroundColor: Theme.of(context).cardColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class CreatePlanDialogContent extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final SqlDatabase db;
  final AppLanguage lang;
  final VoidCallback onSuccess;

  const CreatePlanDialogContent({
    super.key,
    required this.orders,
    required this.db,
    required this.lang,
    required this.onSuccess,
  });

  @override
  State<CreatePlanDialogContent> createState() => _CreatePlanDialogContentState();
}

class _CreatePlanDialogContentState extends State<CreatePlanDialogContent> {
  Map<String, dynamic>? _selectedOrder;
  List<Map<String, dynamic>> _orderItems = [];
  bool _loadingItems = false;
  
  // Track delivery quantities for each item ID
  Map<int, int> _deliveryQuantities = {};
  DateTime _deliveryDate = DateTime.now();

  Future<void> _onOrderSelected(Map<String, dynamic>? order) async {
    if (order == null) return;
    setState(() {
      _selectedOrder = order;
      _loadingItems = true;
      _orderItems = [];
      _deliveryQuantities = {};
    });

    try {
      final items = await widget.db.readCommandeDetails(int.tryParse(order['id']?.toString() ?? '') ?? 0);
      setState(() {
        _orderItems = items;
        for (var item in items) {
          int itemId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
          int totalQty = int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
          int delQty = int.tryParse(item['delivered_qty']?.toString() ?? '') ?? 0;
          int remaining = totalQty - delQty;
          _deliveryQuantities[itemId] = remaining > 0 ? remaining : 0;
        }
        _loadingItems = false;
      });
    } catch (e) {
      debugPrint("Error loading items: $e");
      setState(() => _loadingItems = false);
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_deliveryDate),
      );
      if (time != null) {
        setState(() {
          _deliveryDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  void _submit() async {
    if (_selectedOrder == null) return;
    
    // Build list of selected items
    List<Map<String, dynamic>> partialItems = [];
    double totalAmount = 0.0;
    bool hasItemsToDeliver = false;

    for (var item in _orderItems) {
      int itemId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
      int qtyToDeliver = _deliveryQuantities[itemId] ?? 0;
      if (qtyToDeliver > 0) {
        hasItemsToDeliver = true;
        // Calculate amount for this item
        double itemPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
        double itemTotal = itemPrice * qtyToDeliver;
        totalAmount += itemTotal;

        // Clone item map and override quantity to the delivery quantity
        var clone = Map<String, dynamic>.from(item);
        clone['quantity'] = qtyToDeliver;
        partialItems.add(clone);
      }
    }

    if (!hasItemsToDeliver) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('الرجاء تحديد كمية أكبر من الصفر لتوصيلها', widget.lang),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final dbInstance = await widget.db.db;
      if (dbInstance == null) return;

      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(_deliveryDate);
      final itemsStr = jsonEncode(partialItems);

      final orderId = int.tryParse(_selectedOrder!['id']?.toString() ?? '') ?? 0;
      final clientId = int.tryParse(_selectedOrder!['client_id']?.toString() ?? '') ?? 0;

      // 1. Insert delivery plan
      await widget.db.insertCommandeDelivery(
        orderId,
        clientId,
        dateStr,
        itemsStr,
        totalAmount,
      );

      // 2. Update delivered quantities in Commandes_details
      for (var item in partialItems) {
        int itemId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
        int qty = int.tryParse(item['quantity']?.toString() ?? '') ?? 0;
        await dbInstance.rawUpdate('''
          UPDATE Commandes_details 
          SET delivered_qty = COALESCE(delivered_qty, 0) + ? 
          WHERE id = ?
        ''', [qty, itemId]);
      }

      // 3. Update order status to partial/full distribution
      final updatedDetails = await widget.db.readCommandeDetails(orderId);
      bool allDelivered = true;
      for (var detail in updatedDetails) {
        int totalQty = int.tryParse(detail['quantity']?.toString() ?? '') ?? 0;
        int delQty = int.tryParse(detail['delivered_qty']?.toString() ?? '') ?? 0;
        if (delQty < totalQty) {
          allDelivered = false;
          break;
        }
      }

      String newStatus = allDelivered ? 'Full Distribution' : 'Partial Distribution';
      await widget.db.updateCommandeStatus(orderId, newStatus);

      widget.onSuccess();
    } catch (e) {
      debugPrint("Error saving delivery plan: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    int? selectedOrderId = _selectedOrder != null
        ? int.tryParse(_selectedOrder!['id']?.toString() ?? '')
        : null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Select Order dropdown
          DropdownButtonFormField<int>(
            value: selectedOrderId,
            hint: Text(
              Localization.translate('اختر الطلبية', widget.lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: widget.orders.map((o) {
              final id = int.tryParse(o['id']?.toString() ?? '') ?? 0;
              final clientName = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}';
              final totalStr = (o['total'] as num?)?.toStringAsFixed(2) ?? '0.00';
              return DropdownMenuItem<int>(
                value: id,
                child: Text(
                  '#$id - $clientName (${totalStr} DA) [${o['status'] ?? ''}]',
                  style: const TextStyle(fontSize: 13, fontFamily: 'Cairo'),
                ),
              );
            }).toList(),
            onChanged: (id) {
              if (id != null) {
                final order = widget.orders.firstWhere(
                  (o) => (int.tryParse(o['id']?.toString() ?? '') ?? 0) == id,
                );
                _onOrderSelected(order);
              }
            },
          ),
          const SizedBox(height: 16),

          if (_loadingItems)
            const Center(child: CircularProgressIndicator())
          else if (_selectedOrder != null) ...[
            Text(
              Localization.translate('تحديد العناصر للشحن:', widget.lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _orderItems.length,
                itemBuilder: (context, index) {
                  final item = _orderItems[index];
                  final itemId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
                  final desc = item['description'] ?? '';
                  final totalQty = int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
                  final delQty = int.tryParse(item['delivered_qty']?.toString() ?? '') ?? 0;
                  final remaining = totalQty - delQty;
                  final currentVal = _deliveryQuantities[itemId] ?? 0;

                  return ListTile(
                    title: Text(
                      '${item['window_type'] ?? ''} (${item['largeur']}x${item['hauteur']})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '$desc\n${Localization.translate('الكمية الكلية:', widget.lang)} $totalQty | ${Localization.translate('المسلم سابقا:', widget.lang)} $delQty',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: currentVal > 0
                              ? () => setState(() => _deliveryQuantities[itemId] = currentVal - 1)
                              : null,
                        ),
                        Text(
                          '$currentVal',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                          onPressed: currentVal < remaining
                              ? () => setState(() => _deliveryQuantities[itemId] = currentVal + 1)
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Date picker
            ListTile(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              title: Text(
                '${Localization.translate('تاريخ التوزيع:', widget.lang)} ${DateFormat('yyyy-MM-dd HH:mm').format(_deliveryDate)}',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
              trailing: const Icon(Icons.calendar_today, color: Colors.blue),
              onTap: _selectDate,
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(Localization.translate('إلغاء', widget.lang), style: const TextStyle(fontFamily: 'Cairo')),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue.shade800,
                    foregroundColor: Theme.of(context).cardColor,
                  ),
                  child: Text(Localization.translate('إنشاء الخطة', widget.lang), style: const TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
