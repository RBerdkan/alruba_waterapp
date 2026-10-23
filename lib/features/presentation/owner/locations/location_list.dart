import 'package:alruba_waterapp/providers/location_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_location_page.dart';
import 'edit_location_page.dart';

class LocationListPage extends ConsumerWidget {
  const LocationListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(locationsProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قائمة المواقع'),
        ),
        body: locationsAsync.when(
          data: (locations) {
            if (locations.isEmpty) {
              return const Center(child: Text('لم يتم العثور على مواقع.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: locations.length,
              itemBuilder: (context, index) {
                final location = locations[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    title: Text(location.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => EditLocationPage(location: location),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) =>
              Center(child: Text('حدث خطأ: ${error.toString()}')),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const AddLocationPage(),
            );
          },
          tooltip: 'إضافة موقع',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
