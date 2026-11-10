import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../ui/ir_page_body.dart';
import '../ui/ir_theme.dart';

class DriverCompensationScreen extends StatefulWidget {
  const DriverCompensationScreen({required this.api, super.key});
  final ApiService api;

  @override
  State<DriverCompensationScreen> createState() =>
      _DriverCompensationScreenState();
}

class _DriverCompensationScreenState extends State<DriverCompensationScreen> {
  Map<String, dynamic>? _account;
  Map<String, dynamic>? _plan;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getDriverCompensation(),
        widget.api.getDriverCompensation(plan: true),
      ]);
      if (mounted) {
        setState(() {
          _account = results[0];
          _plan = results[1];
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No pudimos actualizar tu compensación. Revisa tu conexión y vuelve a intentar.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _pv(dynamic value) {
    final raw = value?.toString() ?? '0';
    final parts = raw.split('.');
    final whole = parts.first
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    final fraction =
        parts.length > 1 ? parts[1].replaceFirst(RegExp(r'0+$'), '') : '';
    return fraction.isEmpty ? whole : '$whole,$fraction';
  }

  String _cash(dynamic value) => 'COP ${_pv(value)}';
  List<Map<String, dynamic>> _rows(dynamic value) => (value as List? ?? [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Sin fecha';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(label),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700))
            ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Compensación conductor'), actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'Actualizar compensación',
              icon: const Icon(Icons.refresh)),
        ]),
        body: Material(
            color: context.irColors.surface,
            child: IrPageBody(
                child: _loading && _account == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                          children: [
                            if (_error != null) ...[
                              Text(_error!),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                      onPressed: _loading ? null : _load,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Volver a intentar'))),
                            ],
                            if (_account != null && _plan != null)
                              ..._content(context),
                          ],
                        )))),
      );

  List<Widget> _content(BuildContext context) {
    final account = _account!;
    final plan = _plan!;
    final unlocked = account['downline_enabled'] == true;
    final pending = (account['pending_rules'] as List? ?? []).cast<String>();
    final payouts = _rows(account['payouts']);
    final incentives = _rows(account['incentives']);
    return [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
            header: true,
            child: Text('Tu plan de compensación',
                style: TextStyle(
                    color: context.irColors.text,
                    fontSize: 30,
                    height: 1.02,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.6))),
        const SizedBox(height: 9),
        Text(
            'Cada viaje validado genera 1 PV por cada \$1.000 de tarifa. El débito de Bolsa IR es del 10%.',
            style: TextStyle(
                color: context.irColors.muted, fontSize: 15, height: 1.42)),
      ]),
      _section('Tus puntos valor', [
        _line('PV personales acumulados', '${_pv(account['personal_pv'])} PV'),
        Text(
            unlocked
                ? 'Ya puedes acumular PV de tu red descendente.'
                : 'Te faltan ${_pv(account['pv_to_unlock'])} PV personales para activar la acumulación de tu red.',
            style: TextStyle(color: context.irColors.muted, height: 1.5)),
        const SizedBox(height: 8),
        const Text(
            'La activación requiere 10.000 PV personales. Los PV del plan se registran por separado de tus PI.'),
      ]),
      _section('Tu red hoy · ${_date(account['today'])}', [
        _line('Lado izquierdo', '${_pv(account['daily_left_pv'])} PV'),
        _line('Lado derecho', '${_pv(account['daily_right_pv'])} PV'),
        const Divider(),
        _line('Grado de hoy',
            account['daily_grade']?.toString() ?? 'Meta pendiente'),
        _line('Puntuación diaria', '${account['daily_score'] ?? 0}'),
        const Text(
            'El grado exige cumplir los PV personales y la meta diaria del lado menor. La comisión semanal requiere alcanzar la meta binomial.'),
        if (account['has_sponsor'] != true)
          const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                  'Tu posición en la red aún no ha sido asignada. Comparte tu código con el equipo de IR.')),
        const SizedBox(height: 10),
        SelectableText('Código de integrante: ${account['member_code']}',
            style: TextStyle(color: context.irColors.muted)),
        TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: account['member_code'].toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Código de integrante copiado')));
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copiar código')),
      ]),
      _section('Maestrías de Excelencia', [
        _line('Maestría alcanzada',
            account['mastery']?.toString() ?? 'Aún sin maestría'),
        Text('Acumulación desde ${_date(account['mastery_period_start'])}'),
        _line('PV personales del período', _pv(account['mastery_personal_pv'])),
        _line('Lado izquierdo del período', _pv(account['mastery_left_pv'])),
        _line('Lado derecho del período', _pv(account['mastery_right_pv'])),
        const Text('Períodos: del 1 al 15 y del 16 al último día del mes.'),
      ]),
      _section('Bonos y liquidaciones', [
        _line('Saldo de bonos abonados', _cash(account['bonus_balance'])),
        if (pending.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Reglas de pago por confirmar'),
            subtitle: const Text('Los PV y el avance siguen registrándose.'),
            children: [
              for (final rule in pending)
                ListTile(dense: true, title: Text(rule))
            ],
          ),
        if (payouts.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                  'Aún no tienes liquidaciones. Aquí aparecerán el período, el monto y la fecha de cada abono.')),
        for (final payout in payouts)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                  '${payout['kind'] == 'weekly' ? 'Comisión semanal' : 'Bono de maestría'} · ${_cash(payout['amount'])}'),
              subtitle: Text(
                  '${_date(payout['start'])} – ${_date(payout['end'])}\n'
                  '${payout['status'] == 'credited' ? 'Abonado' : 'Programado'} · ${_date(payout['payable_on'])}')),
        for (final incentive in incentives)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Incentivo Master ${incentive['mastery']}'),
              subtitle: Text(
                  '${incentive['description']}\n${incentive['status'] == 'delivered' ? 'Entregado' : 'Pendiente de entrega'}')),
      ]),
      _section('Consulta el plan completo', [
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Los 8 grados y sus metas'),
            children: [
              for (final grade in _rows(plan['grades']))
                ListTile(
                    title: Text(
                        'Conductor ${grade['name']} · grado ${grade['degree']}'),
                    subtitle: Text(
                        '${_pv(grade['personal_pv'])} PV personales\n'
                        '${_pv(grade['daily_weak_pv'])} PV diarios en el lado menor · ${grade['score']} puntos'))
            ]),
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Las 7 maestrías y sus incentivos'),
            children: [
              for (final mastery in _rows(plan['masteries']))
                ListTile(
                    title: Text(
                        'Master ${mastery['name']} · ${_pv((double.parse(mastery['rate'].toString()) * 100).toStringAsFixed(1))}%'),
                    subtitle: Text(
                        '${mastery['prerequisite']}\n${mastery['incentive']}'))
            ]),
        const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Distribución del fondo'),
            children: [
              Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                      'El fondo máximo es el 25% de la utilidad neta de las recargas. De ese fondo: '
                      '54% comisión general, 20% maestrías, 6% centro de capacitación y 20% promoción, regalos e incentivos. '
                      'Dentro del 54% general: 80% conductores y 20% bonificaciones y regalos para usuarios.'))
            ]),
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Calendario y condiciones del documento'),
            children: [
              for (final term in (plan['terms'] as List? ?? []))
                Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(term.toString()))
            ]),
        const SizedBox(height: 14),
        Text('Fuente: ${plan['source']}',
            style: TextStyle(color: context.irColors.muted)),
        const SizedBox(height: 8),
        const Text(
            'Los valores de los incentivos son estimados y están sujetos a las condiciones del mercado.'),
      ]),
    ];
  }
}
