import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alruba_waterapp/providers/location_provider.dart';

class EditCustomerPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> customer;

  const EditCustomerPage({super.key, required this.customer});

  @override
  ConsumerState<EditCustomerPage> createState() => _EditCustomerPageState();
}

class _EditCustomerPageState extends ConsumerState<EditCustomerPage> {
  final _formKey = GlobalKey<FormState>();

  late String _name;
  late String _phone;
  String? _preciseLocation;
  String? _type;
  String? _locationId;

  @override
  void initState() {
    super.initState();
    _name = widget.customer['name'] ?? '';
    _phone = widget.customer['phone'] ?? '';
    _preciseLocation = widget.customer['precise_location'] as String?;
    _type = widget.customer['type'] ?? 'regular';
    _locationId = widget.customer['location_id'] as String?;
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    Map<String, dynamic> updatedFields = {};

    if (_name != widget.customer['name']) {
      updatedFields['name'] = _name;
    }
    if (_phone != widget.customer['phone']) {
      updatedFields['phone'] = _phone;
    }
    if (_preciseLocation != null &&
        _preciseLocation!.isNotEmpty &&
        _preciseLocation != widget.customer['precise_location']) {
      updatedFields['precise_location'] = _preciseLocation;
    }
    if (_type != null && _type != widget.customer['type']) {
      updatedFields['type'] = _type;
    }
    if (_locationId != null && _locationId != widget.customer['location_id']) {
      updatedFields['location_id'] = _locationId;
    }

    if (updatedFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد تغييرات ليتم تحديثها'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await Supabase.instance.client
          .from('customers')
          .update(updatedFields)
          .eq('id', widget.customer['id']);

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('تم التحديث'),
          content: const Text('تم تحديث البيانات بنجاح'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, true);
              },
              child: const Text('موافق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في التحديث: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(locationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل بيانات الزبون'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  border: OutlineInputBorder(),
                ),
                onSaved: (v) => _name = v?.trim() ?? '',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'الرجاء إدخال الاسم';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                onSaved: (v) => _phone = v?.trim() ?? '',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'الرجاء إدخال رقم الهاتف';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'نوع العميل',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'regular', child: Text('عادي')),
                  DropdownMenuItem(value: 'distributor', child: Text('موزع')),
                ],
                onChanged: (val) => setState(() => _type = val),
                onSaved: (val) => _type = val,
              ),
              const SizedBox(height: 16),
              locationsAsync.when(
                data: (locations) => DropdownButtonFormField<String>(
                  value: _locationId,
                  decoration: const InputDecoration(
                    labelText: 'المنطقة',
                    border: OutlineInputBorder(),
                  ),
                  items: locations
                      .map((loc) => DropdownMenuItem(
                            value: loc.id,
                            child: Text(loc.name),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => _locationId = val),
                  onSaved: (val) => _locationId = val,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('خطأ في تحميل المناطق: $err'),
              ),
              const SizedBox(height: 16),
              const Text(
                'يمكنك اختيار موقع دقيق جديد أو تركه كما هو',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ExactLocationEditWidget(
                initialLocation: _preciseLocation,
                onLocationSelected: (val) {
                  setState(() {
                    _preciseLocation = val;
                  });
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveCustomer,
                child: const Text('حفظ التغييرات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExactLocationEditWidget extends StatefulWidget {
  final String? initialLocation;
  final ValueChanged<String>? onLocationSelected;

  const ExactLocationEditWidget({
    super.key,
    this.initialLocation,
    this.onLocationSelected,
  });

  @override
  State<ExactLocationEditWidget> createState() =>
      _ExactLocationEditWidgetState();
}

class _ExactLocationEditWidgetState extends State<ExactLocationEditWidget> {
  late TextEditingController _exactLocationCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _exactLocationCtrl =
        TextEditingController(text: widget.initialLocation ?? '');
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _loading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception("تم تعطيل خدمات الموقع.");
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception("تم رفض صلاحيات الموقع.");
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception("تم رفض صلاحيات الموقع بشكل دائم.");
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final coords =
          '${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}';

      if (!mounted) return;
      setState(() {
        _exactLocationCtrl.text = coords;
        _loading = false;
      });

      widget.onLocationSelected?.call(coords);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("حدث خطأ أثناء الحصول على الموقع: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _exactLocationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.my_location),
          label: Text(
              _loading ? 'جاري تحديد الموقع...' : 'احصل على الموقع الحالي'),
          onPressed: _loading ? null : _getCurrentLocation,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _exactLocationCtrl,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'الموقع الدقيق',
            hintText: 'اضغط على "احصل على الموقع الحالي" للملء',
            border: const OutlineInputBorder(),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          validator: (_) {
            // Do not force location field to be non-empty
            // Let user keep current or empty
            return null;
          },
        ),
      ],
    );
  }
}
