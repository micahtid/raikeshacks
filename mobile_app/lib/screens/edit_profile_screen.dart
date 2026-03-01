import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend_service.dart';
import '../theme.dart';

// ── Enum ↔ display-label maps ─────────────────────────────────────────────

const _focusDisplayToEnum = <String, String>{
  'Startup': 'startup',
  'Research': 'research',
  'Side Project': 'side_project',
  'Open Source': 'open_source',
  'Looking for opportunities': 'looking',
};
final _focusEnumToDisplay = {
  for (final e in _focusDisplayToEnum.entries) e.value: e.key,
};

const _focusIcons = <String, IconData>{
  'Startup': Icons.rocket_launch_rounded,
  'Research': Icons.science_rounded,
  'Side Project': Icons.handyman_rounded,
  'Open Source': Icons.public_rounded,
  'Looking for opportunities': Icons.work_rounded,
};

const _stageDisplayToEnum = <String, String>{
  'Idea': 'idea',
  'MVP': 'mvp',
  'Launched': 'launched',
  'Scaling': 'scaling',
};
final _stageEnumToDisplay = {
  for (final e in _stageDisplayToEnum.entries) e.value: e.key,
};

const _stageIcons = <String, IconData>{
  'Idea': Icons.lightbulb_rounded,
  'MVP': Icons.construction_rounded,
  'Launched': Icons.rocket_rounded,
  'Scaling': Icons.trending_up_rounded,
};

const _domainSuggestions = [
  'HealthTech',
  'EdTech',
  'Climate',
  'B2B SaaS',
  'FinTech',
  'AI/ML',
  'E-commerce',
  'Social',
  'Gaming',
  'Developer Tools',
];

/// Safely extract skill name strings from a list of `{name, source/priority}` maps.
List<String> _extractSkillNames(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .map((s) => s is Map ? s['name']?.toString() ?? '' : '')
      .where((n) => n.isNotEmpty)
      .toList();
}

// ── EditProfileContent ────────────────────────────────────────────────────

class EditProfileContent extends StatefulWidget {
  final String? userPhotoUrl;
  final String displayName;
  final VoidCallback onSignOut;

  const EditProfileContent({
    super.key,
    this.userPhotoUrl,
    required this.displayName,
    required this.onSignOut,
  });

  @override
  State<EditProfileContent> createState() => _EditProfileContentState();
}

class _EditProfileContentState extends State<EditProfileContent> {
  bool _loading = true;
  bool _saving = false;
  String? _uid;

  Map<String, dynamic> _original = {};

  // Identity
  final _universityCtrl = TextEditingController();
  final _gradYearCtrl = TextEditingController();
  List<String> _majors = [];
  List<String> _minors = [];
  final _majorCtrl = TextEditingController();
  final _minorCtrl = TextEditingController();

  // Focus areas (display labels)
  Set<String> _selectedFocus = {};

  // Project
  final _oneLinerCtrl = TextEditingController();
  String? _selectedStage;
  List<String> _domains = [];
  final _domainCtrl = TextEditingController();

  // Skills (name strings only)
  List<String> _mySkills = [];
  List<String> _lookingFor = [];
  final _skillCtrl = TextEditingController();
  final _lookingForCtrl = TextEditingController();

  String get _firstName => widget.displayName.split(' ').first;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _universityCtrl.dispose();
    _gradYearCtrl.dispose();
    _majorCtrl.dispose();
    _minorCtrl.dispose();
    _oneLinerCtrl.dispose();
    _domainCtrl.dispose();
    _skillCtrl.dispose();
    _lookingForCtrl.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('student_uid');
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _uid = uid;

    final data = await BackendService.getStudent(uid);
    if (!mounted) return;

    if (data == null) {
      setState(() => _loading = false);
      return;
    }

    _original = Map<String, dynamic>.from(data);
    final identity = data['identity'] as Map<String, dynamic>? ?? {};
    final project = data['project'] as Map<String, dynamic>? ?? {};
    final skills = data['skills'] as Map<String, dynamic>? ?? {};
    final focusList = data['focus_areas'] as List? ?? [];

    setState(() {
      _universityCtrl.text = identity['university']?.toString() ?? '';
      _gradYearCtrl.text = identity['graduation_year']?.toString() ?? '';
      _majors = List<String>.from(identity['major'] ?? []);
      _minors = List<String>.from(identity['minor'] ?? []);

      _selectedFocus = focusList
          .map((e) => _focusEnumToDisplay[e.toString()])
          .whereType<String>()
          .toSet();

      _oneLinerCtrl.text = project['one_liner']?.toString() ?? '';
      final stageEnum = project['stage']?.toString();
      _selectedStage =
          stageEnum != null ? _stageEnumToDisplay[stageEnum] : null;
      _domains = List<String>.from(project['industry'] ?? []);

      _mySkills = _extractSkillNames(skills['possessed']);
      _lookingFor = _extractSkillNames(skills['needed']);

      _loading = false;
    });
  }

  // ── Diff & save ──────────────────────────────────────────────────────────

  Map<String, dynamic> _buildPayload() {
    final payload = <String, dynamic>{};
    final origIdentity =
        _original['identity'] as Map<String, dynamic>? ?? {};
    final origProject =
        _original['project'] as Map<String, dynamic>? ?? {};
    final origSkills =
        _original['skills'] as Map<String, dynamic>? ?? {};
    final origFocus = List<String>.from(_original['focus_areas'] ?? []);

    // ── Identity ─────────────────────────────────────────────
    final uni = _universityCtrl.text.trim();
    final gradYear = int.tryParse(_gradYearCtrl.text.trim());
    final origMajors = List<String>.from(origIdentity['major'] ?? []);
    final origMinors = List<String>.from(origIdentity['minor'] ?? []);

    if (uni != (origIdentity['university'] ?? '') ||
        gradYear != origIdentity['graduation_year'] ||
        !_listEquals(_majors, origMajors) ||
        !_listEquals(_minors, origMinors)) {
      payload['identity'] = {
        'full_name': origIdentity['full_name'] ?? widget.displayName,
        'email': origIdentity['email'] ?? '',
        if (origIdentity['profile_photo_url'] != null)
          'profile_photo_url': origIdentity['profile_photo_url'],
        'university': uni,
        'graduation_year': gradYear ?? origIdentity['graduation_year'] ?? 2026,
        'major': _majors,
        'minor': _minors,
      };
    }

    // ── Focus areas ──────────────────────────────────────────
    final newFocusEnums = _selectedFocus
        .map((d) => _focusDisplayToEnum[d])
        .whereType<String>()
        .toList()
      ..sort();
    final sortedOrigFocus = List<String>.from(origFocus)..sort();
    if (!_listEquals(newFocusEnums, sortedOrigFocus)) {
      payload['focus_areas'] = newFocusEnums;
    }

    // ── Project ──────────────────────────────────────────────
    final oneLiner = _oneLinerCtrl.text.trim();
    final stageEnum = _selectedStage != null
        ? _stageDisplayToEnum[_selectedStage!]
        : null;
    final origDomains = List<String>.from(origProject['industry'] ?? []);

    if (oneLiner != (origProject['one_liner'] ?? '') ||
        stageEnum != origProject['stage'] ||
        !_listEquals(_domains, origDomains)) {
      payload['project'] = {
        'one_liner': oneLiner.isNotEmpty ? oneLiner : null,
        'stage': stageEnum,
        'industry': _domains,
      };
    }

    // ── Skills ───────────────────────────────────────────────
    final origPossessed = _extractSkillNames(origSkills['possessed']);
    final origNeeded = _extractSkillNames(origSkills['needed']);

    if (!_listEquals(_mySkills, origPossessed) ||
        !_listEquals(_lookingFor, origNeeded)) {
      // Preserve source/priority for existing skills, default for new ones
      final possessedMap = <String, Map<String, dynamic>>{};
      for (final s in origSkills['possessed'] as List? ?? []) {
        if (s is Map<String, dynamic>) possessedMap[s['name'] ?? ''] = s;
      }
      final neededMap = <String, Map<String, dynamic>>{};
      for (final s in origSkills['needed'] as List? ?? []) {
        if (s is Map<String, dynamic>) neededMap[s['name'] ?? ''] = s;
      }

      payload['skills'] = {
        'possessed': _mySkills.map((name) {
          return possessedMap[name] ??
              {'name': name, 'source': 'questionnaire'};
        }).toList(),
        'needed': _lookingFor.map((name) {
          return neededMap[name] ??
              {'name': name, 'priority': 'nice_to_have'};
        }).toList(),
      };
    }

    return payload;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _save() async {
    final payload = _buildPayload();
    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No changes to save')),
      );
      return;
    }

    setState(() => _saving = true);
    final result = await BackendService.updateStudent(_uid!, payload);
    if (!mounted) return;
    setState(() => _saving = false);

    if (result != null) {
      _original = Map<String, dynamic>.from(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update profile')),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.only(top: 32, bottom: 120),
      children: [
        // Avatar
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 2),
            ),
            child: ClipOval(
              child: widget.userPhotoUrl != null
                  ? Image.network(
                      widget.userPhotoUrl!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: AppColors.surfaceLightBlue,
                      alignment: Alignment.center,
                      child: Text(
                        _firstName.isNotEmpty
                            ? _firstName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.displayName,
          style: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // ── Collapsible sections ────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: Column(
            children: [
              _buildIdentitySection(),
              _buildFocusSection(),
              _buildProjectSection(),
              _buildSkillsSection(),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Save
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('Save'),
          ),
        ),
        const SizedBox(height: 12),

        // Sign Out
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: FilledButton(
            onPressed: widget.onSignOut,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceLightBlue,
              foregroundColor: AppColors.textPrimary,
            ),
            child: const Text('Sign Out'),
          ),
        ),
      ],
    );
  }

  // ── Section builders ─────────────────────────────────────────────────────

  Widget _buildIdentitySection() {
    return _Section(
      title: 'Identity',
      icon: Icons.school_rounded,
      children: [
        _buildTextField('University', _universityCtrl),
        const SizedBox(height: 12),
        _buildTextField('Graduation Year', _gradYearCtrl,
            keyboardType: TextInputType.number),
        const SizedBox(height: 16),
        _buildTagField(
          label: 'Majors',
          tags: _majors,
          controller: _majorCtrl,
          onAdd: (v) => setState(() => _majors.add(v)),
          onRemove: (v) => setState(() => _majors.remove(v)),
        ),
        const SizedBox(height: 16),
        _buildTagField(
          label: 'Minors',
          tags: _minors,
          controller: _minorCtrl,
          onAdd: (v) => setState(() => _minors.add(v)),
          onRemove: (v) => setState(() => _minors.remove(v)),
        ),
      ],
    );
  }

  Widget _buildFocusSection() {
    return _Section(
      title: 'Focus Areas',
      icon: Icons.center_focus_strong_rounded,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _focusDisplayToEnum.keys.map((label) {
            final selected = _selectedFocus.contains(label);
            return GestureDetector(
              onTap: () => setState(() {
                if (selected) {
                  _selectedFocus.remove(label);
                } else {
                  _selectedFocus.add(label);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _focusIcons[label],
                      size: 18,
                      color: selected
                          ? AppColors.onPrimary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? AppColors.onPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildProjectSection() {
    return _Section(
      title: 'Project',
      icon: Icons.rocket_launch_rounded,
      children: [
        _buildTextField('One-liner description', _oneLinerCtrl),
        const SizedBox(height: 16),
        Text(
          'Stage',
          style: GoogleFonts.sora(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _stageDisplayToEnum.keys.map((label) {
            final selected = _selectedStage == label;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedStage = selected ? null : label;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _stageIcons[label],
                      size: 18,
                      color: selected
                          ? AppColors.onPrimary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? AppColors.onPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _buildTagField(
          label: 'Domains',
          tags: _domains,
          controller: _domainCtrl,
          onAdd: (v) => setState(() => _domains.add(v)),
          onRemove: (v) => setState(() => _domains.remove(v)),
          suggestions: _domainSuggestions,
        ),
      ],
    );
  }

  Widget _buildSkillsSection() {
    return _Section(
      title: 'Skills',
      icon: Icons.build_rounded,
      children: [
        _buildTagField(
          label: 'My Skills',
          tags: _mySkills,
          controller: _skillCtrl,
          onAdd: (v) => setState(() => _mySkills.add(v)),
          onRemove: (v) => setState(() => _mySkills.remove(v)),
        ),
        const SizedBox(height: 16),
        _buildTagField(
          label: 'Looking For',
          tags: _lookingFor,
          controller: _lookingForCtrl,
          onAdd: (v) => setState(() => _lookingFor.add(v)),
          onRemove: (v) => setState(() => _lookingFor.remove(v)),
        ),
      ],
    );
  }

  // ── Shared builders ──────────────────────────────────────────────────────

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 14,
          color: AppColors.textTertiary,
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: 16,
          color: AppColors.primary,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),
    );
  }

  Widget _buildTagField({
    required String label,
    required List<String> tags,
    required TextEditingController controller,
    required ValueChanged<String> onAdd,
    required ValueChanged<String> onRemove,
    List<String>? suggestions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Add $label',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                onSubmitted: (v) {
                  final trimmed = v.trim();
                  if (trimmed.isNotEmpty && !tags.contains(trimmed)) {
                    onAdd(trimmed);
                  }
                  controller.clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty && !tags.contains(trimmed)) {
                  onAdd(trimmed);
                }
                controller.clear();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLightBlue,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.add, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map((tag) => _TagChip(
                      label: tag,
                      onRemove: () => onRemove(tag),
                    ))
                .toList(),
          ),
        ],
        if (suggestions != null &&
            suggestions.any((s) => !tags.contains(s))) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .where((s) => !tags.contains(s))
                .map((s) => GestureDetector(
                      onTap: () => onAdd(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.border, width: 0.5),
                        ),
                        child: Text(
                          s,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

// ── Collapsible section ───────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 12, bottom: 16),
          expandedAlignment: Alignment.centerLeft,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Icon(icon, size: 20, color: AppColors.primary),
          title: Text(
            title,
            style: GoogleFonts.sora(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          iconColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          children: children,
        ),
      ),
    );
  }
}

// ── Tag chip ──────────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _TagChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLightBlue,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
