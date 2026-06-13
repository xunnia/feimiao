import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';

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
          return ListView.separated(
            itemCount: accounts.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final account = accounts[index];
              return ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(account.name),
                subtitle: Text(
                  account.currencyCode,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: '改名',
                      onPressed: () =>
                          _showRenameSheet(context, account),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: '删除',
                      onPressed: () =>
                          _confirmDelete(context, repo, account),
                    ),
                  ],
                ),
              );
            },
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text(
          '确认删除「${account.name}」？\n关联的历史记录不会被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
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
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '账户名称',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currencyCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: '币种代码（如 CNY、USD）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '账户名称',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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
