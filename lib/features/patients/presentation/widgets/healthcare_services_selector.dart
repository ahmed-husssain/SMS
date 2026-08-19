import 'package:flutter/material.dart';

class HealthcareServicesSelector extends StatefulWidget {
  final List<Map<String, dynamic>> initialSelectedServices;
  final Function(List<Map<String, dynamic>>, double) onChanged;

  const HealthcareServicesSelector({
    super.key,
    required this.initialSelectedServices,
    required this.onChanged,
  });

  @override
  State<HealthcareServicesSelector> createState() => _HealthcareServicesSelectorState();
}

class _HealthcareServicesSelectorState extends State<HealthcareServicesSelector> {
  // Prices are per-day costs
  final List<Map<String, dynamic>> _availableServices = [
    {'serviceName': 'Online Doctor Consultation', 'dailyPrice': 0.0},
    {'serviceName': 'Home Physiotherapy Services', 'dailyPrice': 3000.0},
    {'serviceName': 'Home Nursing Care Services', 'dailyPrice': 3000.0},
    {'serviceName': 'Home Attendant Service', 'dailyPrice': 2000.0},
    {'serviceName': 'Home Nurse Visit', 'dailyPrice': 2000.0},
    {'serviceName': 'Home NG Tube Insertion', 'dailyPrice': 2500.0},
    {'serviceName': 'Wound & Bed Sore Dressing', 'dailyPrice': 2000.0},
    {'serviceName': 'Home ICU Nurse', 'dailyPrice': 3500.0},
    {'serviceName': 'Medical Equipment', 'dailyPrice': 0.0},
  ];

  late List<Map<String, dynamic>> _selectedServices;

  @override
  void initState() {
    super.initState();
    _selectedServices = List<Map<String, dynamic>>.from(widget.initialSelectedServices);
  }

  bool _isServiceSelected(String serviceName) {
    return _selectedServices.any((s) => s['serviceName'] == serviceName);
  }

  double _calculate30DayTotal() {
    return _selectedServices.fold(0.0, (sum, item) => sum + ((item['dailyPrice'] as double) * 30));
  }

  void _toggleService(Map<String, dynamic> service, bool selected) {
    setState(() {
      if (selected) {
        _selectedServices.add(service);
      } else {
        _selectedServices.removeWhere((s) => s['serviceName'] == service['serviceName']);
      }
    });

    widget.onChanged(_selectedServices, _calculate30DayTotal());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Select Healthcare Services', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 68,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _availableServices.length,
          itemBuilder: (context, index) {
            final service = _availableServices[index];
            final isSelected = _isServiceSelected(service['serviceName']);
            return InkWell(
              onTap: () => _toggleService(service, !isSelected),
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                decoration: BoxDecoration(
                  color: isSelected 
                      ? Colors.blue.shade50
                      : Colors.white,
                  border: Border.all(
                    color: isSelected 
                        ? Colors.blue.shade600
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                    child: Text(
                      service['serviceName'] as String,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        color: isSelected 
                            ? Colors.blue.shade800
                            : Colors.grey.shade800,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
