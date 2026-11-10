from datetime import timedelta
from pathlib import Path

from django.http import FileResponse
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from .compensation import BOGOTA, _bounds, branch_pv, member_for, personal_pv
from .compensation_plan import MASTERIES, PERSONAL_GATE, catalogue, grade_for
from .models import CompensationControl, DriverProfile


def _driver(request):
    profile = DriverProfile.objects.filter(user=request.user).first()
    if profile is None:
        raise PermissionDenied('Este plan de compensación corresponde a conductores.')
    return profile


class CompensationPlanView(APIView):
    def get(self, request):
        _driver(request)
        return Response(catalogue())


class CompensationSourceView(APIView):
    def get(self, request):
        _driver(request)
        source = Path(__file__).parent / 'resources' / 'compensation_plan.pdf'
        return FileResponse(source.open('rb'), content_type='application/pdf',
                            as_attachment=True, filename='PLAN COMPENSACION IR CONDUCTORES.pdf')


class CompensationMeView(APIView):
    def get(self, request):
        profile = _driver(request)
        member = member_for(profile)
        today = timezone.localdate(timezone.now(), BOGOTA)
        lower, upper = _bounds(today, today)
        left, right = branch_pv(member, lower, upper)
        personal = personal_pv(member)
        grade = grade_for(personal, left, right)
        period_start = today.replace(day=1 if today.day <= 15 else 16)
        period_lower, _ = _bounds(period_start, today)
        period_left, period_right = branch_pv(member, period_lower, upper)
        held = member.mastery_awards.order_by('-level').values_list('level', flat=True).first() or 0
        control = CompensationControl.objects.filter(pk=1).first()
        pending = []
        for key, label in (
            ('profit_definition', 'Fórmula de utilidad neta'),
            ('weekly_distribution', 'Fórmula de reparto semanal'),
            ('mastery_base', 'Base de cálculo de maestrías'),
            ('mastery_calendar', 'Calendario de pago de maestrías'),
            ('promotion_terms', 'Aclaración de las condiciones de promoción'),
            ('approval_reference', 'Constancia de aprobación de las reglas'),
        ):
            if not control or not getattr(control, key).strip():
                pending.append(label)
        payouts = member.payouts.select_related('period').order_by('-period__end', '-pk')[:30]
        return Response({
            'personal_pv': str(personal), 'pi': profile.points or 0,
            'downline_enabled': personal >= PERSONAL_GATE,
            'pv_to_unlock': str(max(0, PERSONAL_GATE - personal)),
            'today': today, 'daily_left_pv': str(left), 'daily_right_pv': str(right),
            'daily_grade': grade.name if grade else None, 'daily_score': grade.score if grade else 0,
            'mastery_period_start': period_start,
            'mastery_personal_pv': str(personal_pv(member, start=period_lower, before=upper)),
            'mastery_left_pv': str(period_left), 'mastery_right_pv': str(period_right),
            'mastery': MASTERIES[held - 1].name if held else None,
            'bonus_balance': str(profile.bonus_balance or 0),
            'member_code': str(member.pk), 'network_side': member.side or None,
            'has_sponsor': bool(member.sponsor_id),
            'pending_rules': pending,
            'payouts': [{'amount': str(p.amount), 'kind': p.period.kind,
                         'start': p.period.start, 'end': p.period.end,
                         'payable_on': p.period.payable_on,
                         'status': 'credited' if p.credited_at else 'scheduled'} for p in payouts],
            'incentives': [{'mastery': MASTERIES[i.level - 1].name,
                            'description': i.description, 'status': i.status,
                            'awarded_at': i.awarded_at}
                           for i in member.incentives.order_by('level')],
        })
