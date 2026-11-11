"""Registration-order placement; role-specific points and rewards stay separate."""

from django.db import transaction
from django.db.models import Max

from .models import BinaryPosition, CompensationControl

NETWORK_VERSION = 'arrival-binary-v1'


def lock_control():
    """Shared lock order: control -> new user/ride -> driver balance."""
    return CompensationControl.objects.select_for_update().get(pk=1)


def position_for(user):
    """Append once under lock. Normal registration already holds the same lock."""
    existing = BinaryPosition.objects.filter(user_id=user.pk).first()
    if existing:
        if existing.network_role != user.rol:
            raise ValueError('El rol de la cuenta no coincide con su árbol binario.')
        return existing
    if user.rol not in {'driver', 'passenger'}:
        raise ValueError('La cuenta no corresponde a una red de pasajeros o conductores.')
    with transaction.atomic():
        lock_control()
        # Recheck after waiting for a concurrent registration of this same account.
        existing = BinaryPosition.objects.filter(user_id=user.pk).first()
        if existing:
            return existing
        last = BinaryPosition.objects.filter(network_role=user.rol).aggregate(last=Max('number'))['last'] or 0
        return BinaryPosition.objects.create(user=user, network_role=user.rol, number=last + 1)


def position_for_api(position):
    return {'version': NETWORK_VERSION, 'role': position.network_role,
            'position': position.number, 'parent_position': position.parent_number,
            'side': position.side or None, 'depth': position.depth,
            'placement_rule': 'registration_order'}


@transaction.atomic
def release_temporary_position(user):
    """Only smoke-test accounts at the queue tail can be removed safely.

    Used by existing cloud verification tools, never by a public endpoint.
    Refuse removal if it could renumber or orphan a real later registration.
    """
    if not (user.correo or '').endswith('@example.test'):
        raise ValueError('Solo se pueden retirar posiciones de cuentas temporales de prueba.')
    lock_control()
    position = BinaryPosition.objects.filter(user_id=user.pk).first()
    if position is None:
        return
    if BinaryPosition.objects.filter(network_role=position.network_role, number__gt=position.number).exists():
        raise ValueError('Hay registros posteriores: no se puede retirar esta posición ni reordenar la red.')
    position.delete()
