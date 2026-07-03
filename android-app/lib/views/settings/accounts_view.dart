import 'package:flutter/material.dart';

import '../../widgets/ios_dialogs.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ios_form.dart';

/// 账户管理页：列出账户，支持新增、改名、删除。
class AccountsView extends StatelessWidget {
  const AccountsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户管理'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增账户',
            onPressed: () => _showAddSheet(context),
          ),
        ],
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final accounts = repo.accounts;
          if (accounts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text('还没有账户',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )),
                ],
              ),
            );
          }
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card(scheme),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < accounts.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: 54,
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ListTile(
                        leading: Icon(Icons.account_balance_wallet_outlined,
                            size: 22, color: scheme.onSurfaceVariant),
                        minLeadingWidth: 0,
                        horizontalTitleGap: 12,
                        title: Text(accounts[i].name),
                        subtitle: Text(
                          accounts[i].currencyCode,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontFamily: 'Nunito',
                                  ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: '改名',
                              onPressed: () =>
                                  _showRenameSheet(context, accounts[i]),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: '删除',
                              onPressed: () =>
                                  _confirmDelete(context, repo, accounts[i]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddAccountSheet(),
    );
  }

  void _showRenameSheet(BuildContext context, AccountEntity account) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RenameAccountSheet(account: account),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppRepository repo,
    AccountEntity account,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除账户',
      message: '确认删除「${account.name}」？\n关联的历史记录不会被删除。',
      confirmText: '删除',
      destructive: true,
    );
    if (confirmed) {
      await repo.deleteAccount(account.id);
    }
  }
}

// ---------------------------------------------------------------------------
// 新增账户底部弹层
// ---------------------------------------------------------------------------

class _AddAccountSheet extends StatefulWidget {
  const _AddAccountSheet();

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _currencyCtrl =
      TextEditingController(text: 'CNY');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currencyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 16,
        right: 16,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '新增账户',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: iosInputDecoration(context, hint: '账户名称'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currencyCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration:
                iosInputDecoration(context, hint: '币种代码（如 CNY、USD）'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _nameCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          await context.read<AppRepository>().addAccount(
                                name: _nameCtrl.text.trim(),
                                currencyCode:
                                    _currencyCtrl.text.trim().toUpperCase(),
                              );
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 改名底部弹层
// ---------------------------------------------------------------------------

class _RenameAccountSheet extends StatefulWidget {
  final AccountEntity account;

  const _RenameAccountSheet({required this.account});

  @override
  State<_RenameAccountSheet> createState() => _RenameAccountSheetState();
}

class _RenameAccountSheetState extends State<_RenameAccountSheet> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.account.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 16,
        right: 16,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '修改账户名称',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: iosInputDecoration(context, hint: '账户名称'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _nameCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          await context
                              .read<AppRepository>()
                              .renameAccount(
                                  widget.account.id, _nameCtrl.text.trim());
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
