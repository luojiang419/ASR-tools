import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_theme.dart';
import '../core/snackbar_util.dart';
import '../l10n/app_localizations.dart';
import '../providers/project_list_provider.dart';
import '../widgets/app_bottom_dock.dart';
import '../widgets/theme_mode_toggle_button.dart';

class CreateProjectScreen extends ConsumerStatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  ConsumerState<CreateProjectScreen> createState() =>
      _CreateProjectScreenState();
}

class _CreateProjectScreenState extends ConsumerState<CreateProjectScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(context.loc.t('create_project_title')),
        actions: [
          const ThemeModeToggleButton(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.loc.t('nav_settings'),
            onPressed: () => context.go('/settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.loc.t('create_project_title'),
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.loc.t('create_project_page_description'),
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _nameController,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: context.loc.t('create_project_name'),
                              hintText: context.loc.t(
                                'create_project_name_hint',
                              ),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return context.loc.t(
                                  'create_project_name_required',
                                );
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : () => context.go('/'),
                                child: Text(context.loc.t('cancel')),
                              ),
                              ElevatedButton.icon(
                                onPressed: _isSubmitting ? null : _submit,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add_circle_outline,
                                        size: 18,
                                      ),
                                label: Text(context.loc.t('create')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AppBottomDockLayout(
            center: _buildGlobalDock(context),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalDock(BuildContext context) {
    return AppDockPanel(
      items: [
        AppDockItem(
          label: context.loc.t('dock_projects'),
          icon: Icons.folder_copy_outlined,
          isSelected: false,
          onTap: () => context.go('/'),
          tooltip: context.loc.t('dock_projects'),
        ),
        AppDockItem(
          label: context.loc.t('dock_create_project'),
          icon: Icons.add_circle_outline,
          isSelected: true,
          onTap: () {},
          tooltip: context.loc.t('dock_create_project'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final project = await ref
          .read(projectListProvider.notifier)
          .createProject(_nameController.text.trim());
      if (!mounted) return;
      SnackbarUtil.success(context, context.loc.t('home_project_created'));
      context.go('/project/${project.id}');
    } catch (e) {
      if (!mounted) return;
      SnackbarUtil.error(context, '${context.loc.t('error')}: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
