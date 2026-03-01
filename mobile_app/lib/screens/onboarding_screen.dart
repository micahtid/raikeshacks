import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend_service.dart';
import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onSignOut;
  final String fullName;
  final String email;
  final String? photoUrl;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
    required this.onSignOut,
    required this.fullName,
    required this.email,
    this.photoUrl,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { resume, identity, focus, project, skills }

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0;

  // Resume
  String? _resumeFileName;
  Uint8List? _resumeBytes;
  bool _isParsing = false;
  bool _resumeProcessed = false;

  // Identity
  final _universityController = TextEditingController();
  final _gradYearController = TextEditingController();
  final List<String> _majors = [];
  final List<String> _minors = [];
  final _majorController = TextEditingController();
  final _minorController = TextEditingController();

  // Focus
  final Set<String> _selectedFocuses = {};
  static const _focusOptions = [
    'Startup',
    'Research',
    'Side Project',
    'Open Source',
    'Looking for opportunities',
  ];
  static const _focusIcons = <String, IconData>{
    'Startup': Icons.rocket_launch_rounded,
    'Research': Icons.science_rounded,
    'Side Project': Icons.handyman_rounded,
    'Open Source': Icons.public_rounded,
    'Looking for opportunities': Icons.work_rounded,
  };

  // Project
  final _projectController = TextEditingController();
  String? _selectedStage;
  final Set<String> _selectedDomains = {};
  final _domainController = TextEditingController();
  static const _stageOptions = ['Idea', 'MVP', 'Launched', 'Scaling'];
  static const _stageIcons = <String, IconData>{
    'Idea': Icons.lightbulb_rounded,
    'MVP': Icons.construction_rounded,
    'Launched': Icons.rocket_rounded,
    'Scaling': Icons.trending_up_rounded,
  };
  static const _domainSuggestions = [
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

  // Skills
  final List<String> _mySkills = [];
  final List<String> _seekingSkills = [];
  final _mySkillsController = TextEditingController();
  final _seekingSkillsController = TextEditingController();

  // Track which skills came from resume vs questionnaire
  final Set<String> _resumeSkills = {};

  bool _isSubmitting = false;

  bool get _skipProject =>
      _selectedFocuses.contains('Looking for opportunities');

  List<_Step> get _steps => [
        _Step.resume,
        _Step.identity,
        _Step.focus,
        if (!_skipProject) _Step.project,
        _Step.skills,
      ];

  @override
  void dispose() {
    _universityController.dispose();
    _gradYearController.dispose();
    _majorController.dispose();
    _minorController.dispose();
    _projectController.dispose();
    _domainController.dispose();
    _mySkillsController.dispose();
    _seekingSkillsController.dispose();
    super.dispose();
  }

  void _next() {
    final steps = _steps;
    if (_currentStep < steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _submitAndFinish();
    }
  }

  void _back() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _pickResume() async {
    if (_resumeProcessed) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      setState(() {
        _resumeFileName = file.name;
        _resumeBytes = file.bytes;
      });
      _parseResume();
    }
  }

  Future<void> _parseResume() async {
    if (_resumeBytes == null || _resumeFileName == null) return;

    setState(() => _isParsing = true);

    try {
      final parsed = await BackendService.parseResume(
        _resumeBytes!,
        _resumeFileName!,
      );

      if (parsed != null && mounted) {
        setState(() {
          // Prefill identity fields
          if (parsed['university'] != null) {
            _universityController.text = parsed['university'] as String;
          }
          if (parsed['graduation_year'] != null) {
            _gradYearController.text = parsed['graduation_year'].toString();
          }
          if (parsed['major'] != null) {
            for (final m in (parsed['major'] as List)) {
              final s = m.toString();
              if (s.isNotEmpty && !_majors.contains(s)) _majors.add(s);
            }
          }
          if (parsed['minor'] != null) {
            for (final m in (parsed['minor'] as List)) {
              final s = m.toString();
              if (s.isNotEmpty && !_minors.contains(s)) _minors.add(s);
            }
          }

          // Prefill skills
          if (parsed['skills'] != null) {
            for (final s in (parsed['skills'] as List)) {
              final skill = s.toString();
              if (skill.isNotEmpty && !_mySkills.contains(skill)) {
                _mySkills.add(skill);
                _resumeSkills.add(skill);
              }
            }
          }

          // Prefill domains
          if (parsed['industry'] != null) {
            for (final d in (parsed['industry'] as List)) {
              final domain = d.toString();
              if (domain.isNotEmpty) _selectedDomains.add(domain);
            }
          }

          // Prefill project one-liner
          if (parsed['project_one_liner'] != null) {
            _projectController.text = parsed['project_one_liner'] as String;
          }

          _resumeProcessed = true;
          _isParsing = false;
        });

        // Auto-advance to identity step
        if (_currentStep == 0) {
          setState(() => _currentStep = 1);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isParsing = false);
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            content: Text('Resume parsing failed: $e'),
            actions: [
              TextButton(
                onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text('DISMISS'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _addDomain(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !_selectedDomains.contains(trimmed)) {
      setState(() => _selectedDomains.add(trimmed));
    }
    _domainController.clear();
  }

  void _addSkill(TextEditingController controller, List<String> list) {
    final trimmed = controller.text.trim();
    if (trimmed.isNotEmpty && !list.contains(trimmed)) {
      setState(() => list.add(trimmed));
    }
    controller.clear();
  }

  void _addTag(TextEditingController controller, List<String> list) {
    final trimmed = controller.text.trim();
    if (trimmed.isNotEmpty && !list.contains(trimmed)) {
      setState(() => list.add(trimmed));
    }
    controller.clear();
  }

  static const _focusToEnum = <String, String>{
    'Startup': 'startup',
    'Research': 'research',
    'Side Project': 'side_project',
    'Open Source': 'open_source',
    'Looking for opportunities': 'looking',
  };

  static const _stageToEnum = <String, String>{
    'Idea': 'idea',
    'MVP': 'mvp',
    'Launched': 'launched',
    'Scaling': 'scaling',
  };

  Future<void> _submitAndFinish() async {
    setState(() => _isSubmitting = true);

    final data = {
      'identity': {
        'full_name': widget.fullName,
        'email': widget.email,
        'profile_photo_url': widget.photoUrl,
        'university': _universityController.text.trim().isNotEmpty
            ? _universityController.text.trim()
            : 'Unknown',
        'graduation_year': int.tryParse(_gradYearController.text.trim()) ?? 2025,
        'major': _majors.isNotEmpty ? _majors : ['Undeclared'],
        'minor': _minors,
      },
      'focus_areas': _selectedFocuses
          .map((f) => _focusToEnum[f] ?? f.toLowerCase())
          .toList(),
      'project': {
        'one_liner': _projectController.text.trim().isNotEmpty
            ? _projectController.text.trim()
            : null,
        'stage': _selectedStage != null
            ? _stageToEnum[_selectedStage!]
            : null,
        'industry': _selectedDomains.toList(),
      },
      'skills': {
        'possessed': _mySkills
            .map((s) => {
                  'name': s,
                  'source': _resumeSkills.contains(s) ? 'resume' : 'questionnaire',
                })
            .toList(),
        'needed': _seekingSkills
            .map((s) => {
                  'name': s,
                  'priority': 'must_have',
                })
            .toList(),
      },
    };

    try {
      final result = await BackendService.createStudent(data);
      if (result != null && result['uid'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('student_uid', result['uid'] as String);
        if (mounted) {
          widget.onComplete();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showMaterialBanner(
            MaterialBanner(
              content: const Text('Failed to create profile. Please try again.'),
              actions: [
                TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                  child: const Text('DISMISS'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            content: Text('Failed to create profile: $e'),
            actions: [
              TextButton(
                onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text('DISMISS'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final safeStep = _currentStep.clamp(0, steps.length - 1);
    final step = steps[safeStep];
    final theme = Theme.of(context);
    final isLastStep = safeStep == steps.length - 1;
    final canProceed = !_isParsing && !_isSubmitting;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with sign out
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding, 16, 8, 0,
              ),
              child: Row(
                children: [
                  if (safeStep > 0)
                    GestureDetector(
                      onTap: _back,
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onSignOut,
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
            // Progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding, 12, AppSpacing.screenPadding, 32,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.progressBar),
                child: LinearProgressIndicator(
                  value: (safeStep + 1) / steps.length,
                  minHeight: AppSpacing.progressBarHeight,
                ),
              ),
            ),
            // Content
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: _buildStep(step, theme),
                ),
              ),
            ),
            // Bottom CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                8,
                AppSpacing.screenPadding,
                AppSpacing.screenPadding,
              ),
              child: FilledButton(
                onPressed: canProceed ? _next : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isLastStep ? 'Finish' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(_Step step, ThemeData theme) {
    return switch (step) {
      _Step.resume => _buildResumeStep(theme),
      _Step.identity => _buildIdentityStep(theme),
      _Step.focus => _buildFocusStep(theme),
      _Step.project => _buildProjectStep(theme),
      _Step.skills => _buildSkillsStep(theme),
    };
  }

  // ── Resume ──────────────────────────────────────────────────────────

  Widget _buildResumeStep(ThemeData theme) {
    final hasFile = _resumeFileName != null;
    final disabled = _resumeProcessed;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upload your resume',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sectionGapSmall),
          Text(
            "We'll use it to prefill your profile — you can always skip this.",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sectionGapLarge),
          GestureDetector(
            onTap: disabled ? null : _pickResume,
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: hasFile ? AppColors.primary : AppColors.border,
                strokeWidth: hasFile ? 1.5 : 1,
                radius: 16,
                dashLength: 8,
                gapLength: 5,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 48),
                decoration: BoxDecoration(
                  color: disabled
                      ? AppColors.surfaceGray.withValues(alpha: 0.5)
                      : hasFile
                          ? AppColors.surfaceLightBlue
                          : AppColors.surfaceGray,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _isParsing
                    ? const Column(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          SizedBox(height: 16),
                          Text('Parsing your resume...'),
                        ],
                      )
                    : Column(
                        children: [
                          Icon(
                            hasFile
                                ? Icons.description_rounded
                                : Icons.upload_file_rounded,
                            size: 48,
                            color: hasFile
                                ? AppColors.primary
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFile
                                ? _resumeFileName!
                                : 'Tap to upload your resume',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: hasFile
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            disabled
                                ? 'Resume processed'
                                : hasFile
                                    ? 'Tap to change file'
                                    : 'PDF, DOC, or DOCX',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (hasFile && !_isParsing && !disabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _resumeFileName!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _resumeFileName = null;
                    _resumeBytes = null;
                  }),
                  child: const Icon(Icons.close, size: 20, color: AppColors.textTertiary),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sectionGapSmall),
          if (!_isParsing)
            Center(
              child: TextButton(
                onPressed: _next,
                child: const Text('Skip for now'),
              ),
            ),
        ],
      ),
    );
  }

  // ── Identity ────────────────────────────────────────────────────────

  Widget _buildIdentityStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us about yourself',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sectionGapSmall),
          Text(
            'Where are you in your academic journey?',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          Text('University', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _universityController,
            decoration: const InputDecoration(
              hintText: 'e.g. University of Nebraska-Lincoln',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          Text('Graduation Year', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _gradYearController,
            decoration: const InputDecoration(
              hintText: 'e.g. 2026',
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          Text('Major(s)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _buildTagInput(
            controller: _majorController,
            tags: _majors,
            hint: 'e.g. Computer Science',
            onAdd: () => _addTag(_majorController, _majors),
            onRemove: (tag) => setState(() => _majors.remove(tag)),
          ),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          Text('Minor(s)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _buildTagInput(
            controller: _minorController,
            tags: _minors,
            hint: 'e.g. Mathematics',
            onAdd: () => _addTag(_minorController, _minors),
            onRemove: (tag) => setState(() => _minors.remove(tag)),
          ),
          const SizedBox(height: AppSpacing.screenPadding),
        ],
      ),
    );
  }

  // ── Focus ───────────────────────────────────────────────────────────

  Widget _buildFocusStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What are you\nworking on?",
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sectionGapSmall),
          Text(
            'Pick as many as you like.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          ..._focusOptions.map((option) {
            final selected = _selectedFocuses.contains(option);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.listItemGap),
              child: _SelectionItem(
                icon: _focusIcons[option],
                label: option,
                selected: selected,
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedFocuses.remove(option);
                    } else {
                      _selectedFocuses.add(option);
                    }
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Project ─────────────────────────────────────────────────────────

  Widget _buildProjectStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Let's hear about\nyour project",
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          // One-liner
          Text('Describe it in one line', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _projectController,
            decoration: const InputDecoration(
              hintText: 'e.g. "Airbnb for lab equipment"',
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          // Stage
          Text('What stage is your project?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          ..._stageOptions.map((stage) {
            final selected = _selectedStage == stage;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.listItemGap),
              child: _SelectionItem(
                icon: _stageIcons[stage],
                label: stage,
                selected: selected,
                onTap: () {
                  setState(() => _selectedStage = selected ? null : stage);
                },
              ),
            );
          }),
          const SizedBox(height: AppSpacing.sectionGapSmall),
          // Domain / industry
          Text('What industry are you in?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._domainSuggestions.map((domain) {
                final selected = _selectedDomains.contains(domain);
                return _DomainChip(
                  label: domain,
                  selected: selected,
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedDomains.remove(domain);
                      } else {
                        _selectedDomains.add(domain);
                      }
                    });
                  },
                );
              }),
              ..._selectedDomains
                  .where((d) => !_domainSuggestions.contains(d))
                  .map((domain) {
                return _DomainChip(
                  label: domain,
                  selected: true,
                  onTap: () => setState(() => _selectedDomains.remove(domain)),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _domainController,
                  decoration: const InputDecoration(
                    hintText: 'Add custom domain...',
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: _addDomain,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _addDomain(_domainController.text),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: const Icon(Icons.add, color: AppColors.onPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.screenPadding),
        ],
      ),
    );
  }

  // ── Skills ──────────────────────────────────────────────────────────

  Widget _buildSkillsStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Last step — your skills", style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          Text(
            "What skills do you have?",
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          _buildTagInput(
            controller: _mySkillsController,
            tags: _mySkills,
            hint: 'e.g. Machine Learning, UI Design...',
            onAdd: () => _addSkill(_mySkillsController, _mySkills),
            onRemove: (tag) => setState(() {
              _mySkills.remove(tag);
              _resumeSkills.remove(tag);
            }),
          ),
          const SizedBox(height: AppSpacing.sectionGapMedium),
          Text(
            "What skills are you\nlooking for?",
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          _buildTagInput(
            controller: _seekingSkillsController,
            tags: _seekingSkills,
            hint: 'e.g. Financial Modeling, Backend Dev...',
            onAdd: () => _addSkill(_seekingSkillsController, _seekingSkills),
            onRemove: (tag) => setState(() => _seekingSkills.remove(tag)),
          ),
          const SizedBox(height: AppSpacing.screenPadding),
        ],
      ),
    );
  }

  // ── Shared tag-input helper ─────────────────────────────────────────

  Widget _buildTagInput({
    required TextEditingController controller,
    required List<String> tags,
    required String hint,
    required VoidCallback onAdd,
    required void Function(String) onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map((tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLightBlue,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => onRemove(tag),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(hintText: hint),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: const Icon(Icons.add, color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Selection item (replaces FilterChip / ChoiceChip) ─────────────────

class _SelectionItem extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectionItem({
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: AppSpacing.selectionItemHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceLightBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.surfaceLightBlue : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// ── Dashed border painter ─────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(radius),
        ),
      );

    final dashPath = _createDashedPath(path);
    canvas.drawPath(dashPath, paint);
  }

  Path _createDashedPath(Path source) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0, metric.length);
        result.addPath(metric.extractPath(distance, end.toDouble()), Offset.zero);
        distance += dashLength + gapLength;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
}

// ── Domain chip (smaller, inline selection) ───────────────────────────

class _DomainChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DomainChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceLightBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.surfaceLightBlue : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AppColors.primary : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
