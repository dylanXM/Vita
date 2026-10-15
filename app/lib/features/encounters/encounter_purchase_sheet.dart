import 'package:flutter/material.dart';
import 'package:get/get.dart';

const _rose = Color(0xFFEBA2B8);
const _ink = Color(0xFF1D151F);

Future<T?> showEncounterSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB30E0910),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _rose, surface: _ink),
          filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
            backgroundColor: _rose, foregroundColor: _ink,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          )),
        ),
        child: Container(
          constraints: BoxConstraints(maxHeight:
            (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * .85),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF352332), _ink, Color(0xFF251924)]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: const Color(0x35EBA2B8)),
          ),
          child: SafeArea(top: false, child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: DefaultTextStyle(
              style: const TextStyle(color: Color(0xFFF6EAF0), fontSize: 14, height: 1.5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 32, height: 3, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: const Color(0x55EBA2B8),
                    borderRadius: BorderRadius.circular(3))),
                child,
              ]),
            ),
          )),
        ),
      ),
    ),
  );
}

class EncounterSheetContent extends StatelessWidget {
  const EncounterSheetContent({super.key, required this.title, required this.icon,
    required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(color: const Color(0x18EBA2B8),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0x30EBA2B8))),
          child: Icon(icon, color: _rose, size: 23)),
        const SizedBox(width: 14),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w500))),
        IconButton(tooltip: 'encounter.cancel'.tr,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20)),
      ]),
      const SizedBox(height: 24),
      ...children,
    ],
  );
}

class EncounterProductTile extends StatelessWidget {
  const EncounterProductTile({super.key, required this.product, required this.onTap});
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(color: const Color(0x0DFFE3EF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x22EBA2B8))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: SizedBox(height: 88,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text('${product['emoji'] ?? '♡'}', style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 16),
            Expanded(child: Text('${product['name_key'] ?? ''}'.tr, maxLines: 2,
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
            const SizedBox(width: 12),
            Text('${product['coins']} ◈', style: const TextStyle(color: _rose, fontSize: 14)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white38),
          ]),
        ),
      )),
    ),
  );
}

class EncounterDemandSheet extends StatefulWidget {
  const EncounterDemandSheet({super.key});
  @override
  State<EncounterDemandSheet> createState() => _EncounterDemandSheetState();
}

class _EncounterDemandSheetState extends State<EncounterDemandSheet> {
  final _text = TextEditingController();
  @override
  void dispose() { _text.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => EncounterSheetContent(
    title: 'encounter.demand'.tr, icon: Icons.auto_awesome_outlined,
    children: [
      TextField(controller: _text, maxLength: 500, minLines: 3, maxLines: 5,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(color: Color(0xFFF6EAF0), height: 1.6),
        decoration: InputDecoration(hintText: 'encounter.demandHint'.tr,
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true, fillColor: const Color(0x440F0A12),
          contentPadding: const EdgeInsets.all(18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0x35EBA2B8))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0x35EBA2B8))))),
      const SizedBox(height: 18),
      FilledButton(onPressed: _text.text.trim().isEmpty ? null
        : () => Navigator.of(context).pop(_text.text.trim()),
        child: Text('encounter.continue'.tr)),
    ],
  );
}
