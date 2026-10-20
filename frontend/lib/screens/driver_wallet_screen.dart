import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_components.dart';
import '../ui/ir_format.dart';
import '../ui/ir_page_body.dart';
import '../ui/ir_theme.dart';

class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(text: '50000');
  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.api.getDriverMe();
      if (mounted) {
        setState(() {
          _profile = profile;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'No se pudo actualizar tu cartera. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recharge() async {
    if (_saving || _confirming || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final amount = int.parse(_amount.text.trim());
    setState(() => _confirming = true);
    try {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: const Text('Confirmar recarga'),
                  content:
                      Text('Vas a recargar ${irMoney(amount)} en tu cartera.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Confirmar'))
                  ]));
      if (confirmed != true || !mounted) return;
      setState(() => _saving = true);
      await widget.api.driverWalletRecharge(amount);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Recarga registrada: ${irMoney(amount)}.')));
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo registrar la recarga. Revisa la conexión e inténtalo de nuevo.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cartera')),
        body: IrEditorialBackdrop(
          child: IrPageBody(
            child: _loading
                ? const Center(
                    child: IrLoadingState(
                        label: 'Cargando tu cartera', compact: true))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                      children: [
                        const IrPageIntro(
                          title: 'Bolsa IR',
                          description:
                              'Controla el saldo disponible para seguir operando.',
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[
                          IrInlineMessage(
                              message: _error!, error: true, onRetry: _load),
                          const SizedBox(height: 20),
                        ],
                        if (_profile != null) ...[
                          IrPanel(
                            accent: true,
                            padding: const EdgeInsets.all(22),
                            child: Column(children: [
                              _balance(
                                  'Saldo total', _profile!['wallet_balance']),
                              _balance('Reservado para viajes',
                                  _profile!['reserved_balance']),
                              Divider(
                                  color: IrPalette.ink.withValues(alpha: .18)),
                              _balance(
                                'Disponible',
                                _profile!['available_balance'] ??
                                    ((num.tryParse(_profile!['wallet_balance']
                                                .toString()) ??
                                            0) -
                                        (num.tryParse(
                                                _profile!['reserved_balance']
                                                    .toString()) ??
                                            0)),
                                prominent: true,
                              ),
                            ]),
                          ),
                          const SizedBox(height: 18),
                          IrPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Recargar cartera',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -.5)),
                                const SizedBox(height: 6),
                                Text('Define el monto antes de confirmarlo.',
                                    style: TextStyle(
                                        color: context.irColors.muted)),
                                const SizedBox(height: 20),
                                Form(
                                  key: _form,
                                  child: TextFormField(
                                    controller: _amount,
                                    enabled: !_saving,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _recharge(),
                                    decoration: const InputDecoration(
                                      labelText: 'Monto en COP',
                                      helperText: 'Mínimo COP 5.000',
                                      prefixIcon: Icon(Icons.payments_outlined),
                                    ),
                                    validator: (value) {
                                      final amount =
                                          int.tryParse(value?.trim() ?? '');
                                      if (amount == null || amount < 5000) {
                                        return 'Ingresa al menos COP 5.000.';
                                      }
                                      if (amount > 99999999) {
                                        return 'El monto supera el máximo permitido.';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 22),
                                FilledButton(
                                  onPressed:
                                      _saving || _confirming ? null : _recharge,
                                  child: _saving
                                      ? const SizedBox.square(
                                          dimension: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Text('Revisar recarga'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      );

  Widget _balance(String label, dynamic amount, {bool prominent = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 24,
          runSpacing: 6,
          children: [
            Text(label,
                style: TextStyle(
                    color: IrPalette.ink.withValues(alpha: .68),
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            Text(irMoney(amount),
                style: TextStyle(
                    color: IrPalette.ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                    fontSize: prominent ? 24 : 18)),
          ],
        ),
      );
}
