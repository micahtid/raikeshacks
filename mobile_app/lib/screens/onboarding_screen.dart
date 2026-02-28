import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onSignOut;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
    required this.onSignOut,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { resume, focus, project, skills }

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0;

  // Resume
  String? _resumeFileName;

  // Screen 1 — Focus
  final Set<String> _selectedFocuses = {};
  static const _focusOptions = [
    'Startup',
    'Research',
    'Side Project',
    'Open Source',
    'Looking for opportunities',
  ];

  // Screen 2 — Project
  final _projectController = TextEditingController();
  String? _selectedStage;
  final Set<String> _selectedDomains = {};
  final _domainController = TextEditingController();
  static const _stageOptions = ['Idea', 'MVP', 'Launched', 'Scaling'];
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

  // Screen 3 — Skills
  final List<String> _mySkills = [];
  final List<String> _seekingSkills = [];
  final _mySkillsController = TextEditingController();
  final _seekingSkillsController = TextEditingController();

  bool get _skipProject =>
      _selectedFocuses.contains('Looking for opportunities');

  List<_Step> get _steps => [
        _Step.resume,
        _Step.focus,
        if (!_skipProject) _Step.project,
        _Step.skills,
      ];

  @override
  void dispose() {
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
      widget.onComplete();
    }
  }

  void _back() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _pickResume() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _resumeFileName = result.files.first.name);
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

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final safeStep = _currentStep.clamp(0, steps.length - 1);
    final step = steps[safeStep];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Get Started'),
        backgroundColor: colors.inversePrimary,
        actions: [
          TextButton(
            onPressed: widget.onSignOut,
            child: const Text('Sign Out'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (safeStep + 1) / steps.length,
            backgroundColor: colors.surfaceContainerHighest,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Step ${safeStep + 1} of ${steps.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(step),
                child: _buildStep(step, theme, colors),
              ),
            ),
          ),
          // Navigation buttons
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  if (safeStep > 0)
                    OutlinedButton(
                      onPressed: _back,
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(
                      safeStep == steps.length - 1 ? 'Finish' : 'Next',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(_Step step, ThemeData theme, ColorScheme colors) {
    return switch (step) {
      _Step.resume => _buildResumeStep(theme, colors),
      _Step.focus => _buildFocusStep(theme, colors),
      _Step.project => _buildProjectStep(theme, colors),
      _Step.skills => _buildSkillsStep(theme, colors),
    };
  }

  // ── Resume ──────────────────────────────────────────────────────────

  Widget _buildResumeStep(ThemeData theme, ColorScheme colors) {
    final hasFile = _resumeFileName != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Drop your resume here', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'No pressure — just helps us get to know you faster.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Material(
            color: hasFile ? colors.primaryContainer : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _pickResume,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 48),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasFile ? colors.primary : colors.outlineVariant,
                    width: hasFile ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      hasFile ? Icons.description : Icons.upload_file,
                      size: 48,
                      color: hasFile
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasFile ? _resumeFileName! : 'Tap to upload your resume',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: hasFile
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                        fontWeight:
                            hasFile ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFile ? 'Tap to change file' : 'PDF, DOC, or DOCX',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hasFile
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasFile) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.check_circle, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _resumeFileName!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 20, color: colors.error),
                  onPressed: () => setState(() => _resumeFileName = null),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
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

  // ── Focus ───────────────────────────────────────────────────────────

  Widget _buildFocusStep(ThemeData theme, ColorScheme colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("What's keeping you busy?",
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Pick as many as you like.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _focusOptions.map((option) {
              final selected = _selectedFocuses.contains(option);
              return FilterChip(
                label: Text(option),
                selected: selected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedFocuses.add(option);
                    } else {
                      _selectedFocuses.remove(option);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Project ─────────────────────────────────────────────────────────

  Widget _buildProjectStep(ThemeData theme, ColorScheme colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Let's hear about your project",
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 24),
          // One-liner
          Text('Sum it up in a sentence', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _projectController,
            decoration: const InputDecoration(
              hintText: 'e.g. "Airbnb for lab equipment"',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 24),
          // Stage
          Text('Where are things at?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _stageOptions.map((stage) {
              return ChoiceChip(
                label: Text(stage),
                selected: _selectedStage == stage,
                onSelected: (val) {
                  setState(() => _selectedStage = val ? stage : null);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          // Domain / industry
          Text('What space are you in?',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._domainSuggestions.map((domain) {
                final selected = _selectedDomains.contains(domain);
                return FilterChip(
                  label: Text(domain),
                  selected: selected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedDomains.add(domain);
                      } else {
                        _selectedDomains.remove(domain);
                      }
                    });
                  },
                );
              }),
              // Custom domains the user typed in
              ..._selectedDomains
                  .where((d) => !_domainSuggestions.contains(d))
                  .map((domain) {
                return Chip(
                  label: Text(domain),
                  onDeleted: () =>
                      setState(() => _selectedDomains.remove(domain)),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _domainController,
                  decoration: const InputDecoration(
                    hintText: 'Add custom domain...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: _addDomain,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _addDomain(_domainController.text),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Skills ──────────────────────────────────────────────────────────

  Widget _buildSkillsStep(ThemeData theme, ColorScheme colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Almost there!", style: theme.textTheme.headlineSmall),
          const SizedBox(height: 24),
          Text(
            "What are you great at?",
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildTagInput(
            controller: _mySkillsController,
            tags: _mySkills,
            hint: 'e.g. Machine Learning, UI Design...',
            onAdd: () => _addSkill(_mySkillsController, _mySkills),
            onRemove: (tag) => setState(() => _mySkills.remove(tag)),
          ),
          const SizedBox(height: 32),
          Text(
            "What would your dream collaborator bring?",
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildTagInput(
            controller: _seekingSkillsController,
            tags: _seekingSkills,
            hint: 'e.g. Financial Modeling, Backend Dev...',
            onAdd: () => _addSkill(_seekingSkillsController, _seekingSkills),
            onRemove: (tag) => setState(() => _seekingSkills.remove(tag)),
          ),
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
                .map((tag) => Chip(
                      label: Text(tag),
                      onDeleted: () => onRemove(tag),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
