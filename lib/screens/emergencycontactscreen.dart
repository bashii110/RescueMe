import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_screen.dart';
import '../services/contacts_notifier.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen>
    with SingleTickerProviderStateMixin {
  List<EmergencyContact> _contacts = [];
  bool _isLoading = true;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _loadContacts();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = prefs.getStringList('emergency_contacts') ?? [];
      setState(() {
        _contacts = contactsJson.map((json) {
          final parts = json.split('|');
          return EmergencyContact(name: parts[0], phoneNumber: parts[1]);
        }).toList();
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('emergency_contacts',
        _contacts.map((c) => '${c.name}|${c.phoneNumber}').toList());
    ContactsNotifier.instance.notify(); // tell home screen to refresh
  }

  void _addContact() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ContactDialog(
        onSave: (name, phone) async {
          setState(
                  () => _contacts.add(EmergencyContact(name: name, phoneNumber: phone)));
          await _saveContacts();
          _showSnackBar('Contact added', AppTheme.success);
        },
      ),
    );
  }

  void _editContact(int index) {
    final c = _contacts[index];
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ContactDialog(
        initialName: c.name,
        initialPhone: c.phoneNumber,
        onSave: (name, phone) async {
          setState(() =>
          _contacts[index] = EmergencyContact(name: name, phoneNumber: phone));
          await _saveContacts();
          _showSnackBar('Contact updated', AppTheme.success);
        },
      ),
    );
  }

  void _deleteContact(int index) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withValues(alpha: 0.1),
                ),
                child: const Icon(Icons.person_remove_rounded,
                    color: AppTheme.accent, size: 24),
              ),
              const SizedBox(height: 16),
              Text('REMOVE CONTACT?',
                  style: AppTheme.displayFont.copyWith(
                      fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              Text('Remove ${_contacts[index].name} from emergency contacts?',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyFont.copyWith(fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('CANCEL',
                          style: AppTheme.displayFont
                              .copyWith(fontSize: 13, color: AppTheme.textSecondary, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        setState(() => _contacts.removeAt(index));
                        await _saveContacts();
                        _showSnackBar('Contact removed', AppTheme.warning);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('REMOVE',
                          style: AppTheme.displayFont.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: AppTheme.bodyFont
              .copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            Text('EMERGENCY',
                style: AppTheme.displayFont.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: AppTheme.accent,
                )),
            const SizedBox(width: 6),
            Text('CONTACTS', style: AppTheme.displayFont.copyWith(
              fontSize: 16, fontWeight: FontWeight.w700,
              letterSpacing: 3, color: Colors.white,
            )),
            Text('${_contacts.length} contacts',
                style: AppTheme.bodyFont.copyWith(fontSize: 11)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.border),
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: AppTheme.accent))
          : _contacts.isEmpty
          ? _buildEmptyState()
          : _buildContactsList(),
      floatingActionButton: _buildAddFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.bgCard,
                border: Border.all(color: AppTheme.border, width: 2),
              ),
              child: const Icon(Icons.group_add_rounded,
                  size: 44, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            Text('NO CONTACTS YET',
                style: AppTheme.displayFont.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 10),
            Text(
                'Add emergency contacts who will receive SMS alerts when an accident is detected.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyFont.copyWith(fontSize: 13, height: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    return Column(
      children: [
        // Info banner
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppTheme.accent.withValues(alpha: 0.06),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppTheme.accent, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'These contacts receive automatic SMS alerts with your GPS location.',
                    style: AppTheme.bodyFont
                        .copyWith(fontSize: 12, color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            itemCount: _contacts.length,
            itemBuilder: (context, index) {
              final contact = _contacts[index];
              final colors = [
                AppTheme.accent,
                AppTheme.success,
                AppTheme.warning,
                const Color(0xFF42A5F5),
                const Color(0xFFAB47BC),
              ];
              final color = colors[index % colors.length];

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.12),
                      border:
                      Border.all(color: color.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Center(
                      child: Text(
                        contact.name[0].toUpperCase(),
                        style: AppTheme.displayFont.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                    ),
                  ),
                  title: Text(contact.name,
                      style: AppTheme.displayFont.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  subtitle: Text(contact.phoneNumber,
                      style: AppTheme.bodyFont.copyWith(fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _iconBtn(Icons.edit_rounded, AppTheme.textSecondary,
                              () => _editContact(index)),
                      const SizedBox(width: 4),
                      _iconBtn(Icons.delete_outline_rounded, AppTheme.accent,
                              () => _deleteContact(index)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: color.withValues(alpha: 0.08),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildAddFab() {
    return GestureDetector(
      onTap: _addContact,
      child: Container(
        height: 56,
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [AppTheme.accent, AppTheme.accentDark],
          ),
          boxShadow: [
            BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: 1)
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('ADD CONTACT',
                style: AppTheme.displayFont.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class EmergencyContact {
  final String name;
  final String phoneNumber;
  EmergencyContact({required this.name, required this.phoneNumber});
}

// ─── Contact Dialog ───────────────────────────────────
class _ContactDialog extends StatefulWidget {
  final String? initialName;
  final String? initialPhone;
  final Function(String, String) onSave;
  const _ContactDialog(
      {this.initialName, this.initialPhone, required this.onSave});

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialName);
    _phoneController =
        TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      widget.onSave(
          _nameController.text.trim(), _phoneController.text.trim());
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accent.withValues(alpha: 0.1),
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: AppTheme.accent, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                    widget.initialName == null
                        ? 'ADD CONTACT'
                        : 'EDIT CONTACT',
                    style: AppTheme.displayFont.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
              ]),
              const SizedBox(height: 24),
              _buildField(_nameController, 'Full Name',
                  Icons.person_outline_rounded, (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Enter a name';
                    }
                    return null;
                  }),
              const SizedBox(height: 14),
              _buildField(
                  _phoneController,
                  'Phone Number (+923001234567)',
                  Icons.phone_outlined, (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Enter phone number';
                }
                if (val.trim().length < 10) {
                  return 'Enter a valid phone number';
                }
                return null;
              }, type: TextInputType.phone),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('CANCEL',
                        style: AppTheme.displayFont.copyWith(
                            fontSize: 13,
                            letterSpacing: 1,
                            color: AppTheme.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('SAVE',
                        style: AppTheme.displayFont.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Colors.white)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
      TextEditingController controller,
      String hint,
      IconData icon,
      String? Function(String?) validator, {
        TextInputType type = TextInputType.text,
      }) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      validator: validator,
      style: AppTheme.bodyFont
          .copyWith(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
        AppTheme.bodyFont.copyWith(color: AppTheme.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 18),
        filled: true,
        fillColor: AppTheme.bgCardLight,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.accent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.accent),
        ),
      ),
    );
  }
}