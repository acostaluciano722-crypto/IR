"""Operator interface: financial inputs never come from an untrusted client."""

import json
from datetime import date
from decimal import InvalidOperation

from django.core.exceptions import ObjectDoesNotExist, ValidationError
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from coredata.compensation import (CompensationError, close_period, credit_due_payouts,
                                   lock_control, member_for, place_member, record_funding)
from coredata.compensation_plan import PLAN_VERSION
from coredata.models import CompensationMember, DriverProfile


class Command(BaseCommand):
    help = 'Administra el plan PDF: estado, reglas, ubicación binaria, fondos, cierres y abonos.'

    def add_arguments(self, parser):
        parser.add_argument('operation', choices=['status', 'configure', 'enroll', 'place', 'fund', 'close', 'credit'])
        parser.add_argument('--driver', help='UUID del perfil de conductor')
        parser.add_argument('--member', help='Código del integrante')
        parser.add_argument('--sponsor', help='Código del patrocinador')
        parser.add_argument('--parent', help='Código del ancestro estructural')
        parser.add_argument('--side', choices=['left', 'right'])
        parser.add_argument('--recharge', help='UUID de recarga real verificada')
        parser.add_argument('--net-profit')
        parser.add_argument('--evidence')
        parser.add_argument('--kind', choices=['weekly', 'mastery'])
        parser.add_argument('--start', type=date.fromisoformat)
        parser.add_argument('--end', type=date.fromisoformat)
        parser.add_argument('--payable-on', type=date.fromisoformat)
        parser.add_argument('--profit-definition')
        parser.add_argument('--weekly-distribution', choices=['sum_daily_scores'])
        parser.add_argument('--mastery-base', choices=['fund_25_percent'])
        parser.add_argument('--mastery-calendar')
        parser.add_argument('--promotion-terms')
        parser.add_argument('--approval-reference')

    def handle(self, *args, **options):
        operation = options['operation']
        try:
            with transaction.atomic():
                control = lock_control()
                if operation == 'status':
                    result = {'version': PLAN_VERSION, 'members': CompensationMember.objects.count(),
                              'weekly_distribution': control.weekly_distribution,
                              'mastery_base': control.mastery_base,
                              'profit_definition': control.profit_definition,
                              'approval_reference': control.approval_reference}
                elif operation == 'configure':
                    fields = ['profit_definition', 'weekly_distribution', 'mastery_base',
                              'mastery_calendar', 'promotion_terms', 'approval_reference']
                    if not options['approval_reference']:
                        raise CompensationError('La configuración requiere --approval-reference.')
                    for field in fields:
                        if options[field] is not None:
                            if not options[field].strip():
                                raise CompensationError('Las reglas aprobadas no pueden estar vacías.')
                            setattr(control, field, options[field])
                    control.save()
                    result = {'configured': True, 'approval_reference': control.approval_reference}
                elif operation == 'enroll':
                    self.require(options, 'driver')
                    result = {'member': str(member_for(DriverProfile.objects.get(pk=options['driver'])).pk)}
                elif operation == 'place':
                    self.require(options, 'member', 'sponsor', 'parent', 'side')
                    member = place_member(CompensationMember.objects.get(pk=options['member']),
                        CompensationMember.objects.get(pk=options['sponsor']),
                        CompensationMember.objects.get(pk=options['parent']), options['side'])
                    result = {'placed': str(member.pk)}
                elif operation == 'fund':
                    self.require(options, 'recharge', 'net_profit', 'evidence')
                    entry = record_funding(options['recharge'], options['net_profit'], options['evidence'])
                    result = {'funding': str(entry.pk), 'net_profit': str(entry.net_profit)}
                elif operation == 'close':
                    self.require(options, 'kind', 'start', 'end', 'payable_on')
                    period = close_period(options['kind'], options['start'], options['end'], options['payable_on'])
                    result = {'period': str(period.pk), 'budget': str(period.budget),
                              'distributed': str(period.distributed), 'reserves': period.reserves}
                else:
                    result = {'credited': credit_due_payouts()}
        except (ValueError, InvalidOperation, ObjectDoesNotExist, ValidationError) as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(json.dumps(result, ensure_ascii=True))

    @staticmethod
    def require(options, *fields):
        missing = [field.replace('_', '-') for field in fields if options[field] is None]
        if missing:
            raise CompensationError('Faltan argumentos: --' + ', --'.join(missing))
