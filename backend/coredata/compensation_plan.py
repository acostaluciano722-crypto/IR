"""Versioned transcription of PLAN COMPENSACION IR CONDUCTORES.pdf (5 pages).

PV are deliberately independent of the application's existing PI. The user
confirmed 1 PV / COP 1,000 on completed trips and the 10% trip debit.
"""

from dataclasses import asdict, dataclass
from decimal import Decimal, ROUND_DOWN

PLAN_VERSION = 'ir-conductores-pdf-v1'
PERSONAL_GATE = 10_000
COP_PER_PV = Decimal('1000')
CENT = Decimal('0.01')


@dataclass(frozen=True)
class Grade:
    name: str
    degree: int
    personal_pv: int
    daily_weak_pv: int
    score: int


GRADES = (
    Grade('Hierro', 8, 10_000, 300_000, 1),
    Grade('Bronce', 7, 300_000, 700_000, 3),
    Grade('Plata', 6, 900_000, 1_400_000, 5),
    Grade('Oro', 5, 1_500_000, 3_000_000, 8),
    Grade('Platino', 4, 2_000_000, 6_000_000, 10),
    Grade('Zafiro', 3, 3_000_000, 12_000_000, 20),
    Grade('Esmeralda', 2, 4_000_000, 24_000_000, 30),
    Grade('Diamante', 1, 5_000_000, 50_000_000, 50),
)


@dataclass(frozen=True)
class Mastery:
    name: str
    rate: str
    prerequisite: str
    incentive: str
    cash_estimate: int
    travel_tickets: int
    previous_awards: int


MASTERIES = (
    Mastery('Bronce', '0.10', '3.000.000 PV en cada lado. Si el lado menor excede '
            '900.000 PV, se pueden agregar los PV personales del período a ese lado.',
            '$1.000.000 en efectivo', 1_000_000, 0, 0),
    Mastery('Plata', '0.05', '2 Master Bronce en cada lado.',
            'Computadora Laptop o Tablet', 0, 0, 0),
    Mastery('Oro', '0.02', '2 Master Plata en cada lado.',
            '$6.000.000 en efectivo y 2 boletos de avión y hospedaje (5 días, 4 noches)',
            6_000_000, 2, 0),
    Mastery('Platino', '0.012', '2 Master Oro en cada lado; obtener la maestría anterior 3 veces.',
            '$30.000.000 en efectivo y 4 boletos de avión y hospedaje', 30_000_000, 4, 3),
    Mastery('Zafiro', '0.01', '2 Master Platino en cada lado; obtener la maestría anterior 3 veces.',
            '$150.000.000 en efectivo y 4 boletos de avión y hospedaje (11 días, 10 noches)',
            150_000_000, 4, 3),
    Mastery('Esmeralda', '0.005', '2 Master Zafiro en cada lado; obtener la maestría anterior 3 veces.',
            '$900.000.000 en efectivo y 4 boletos de avión y hospedaje (11 días, 10 noches)',
            900_000_000, 4, 3),
    Mastery('Diamante', '0.003', '2 Master Esmeralda en cada lado; obtener la maestría anterior 3 veces.',
            '$3.000.000.000 en efectivo y 4 boletos de avión y hospedaje (11 días, 10 noches)',
            3_000_000_000, 4, 3),
)

OPEN_RULES = {
    'profit_definition': 'Fórmula contable de utilidad neta de las recargas.',
    'weekly_distribution': 'Cómo usar la puntuación diaria en el reparto semanal y día de corte.',
    'mastery_base': 'La tabla dice porcentajes del total de PV, pero el fondo se define en utilidad neta.',
    'mastery_calendar': 'El pago del día 15 se menciona junto con un período que termina ese mismo día.',
    'promotion_terms': 'La restricción menciona Gestor Aire, categoría que no aparece en el plan.',
    'education_calendar': 'Se indican dos pagos al mes, sin fechas exactas ni centro beneficiario.',
    'passenger_distribution': 'No se especifica cómo repartir el 20% para usuarios.',
}


def money(value):
    value = Decimal(str(value))
    if not value.is_finite() or value < 0:
        raise ValueError('El importe debe ser finito y no negativo.')
    return value.quantize(CENT, rounding=ROUND_DOWN)


def split_funds(net_profit):
    """Floor each allocation; leave rounding residual inside the 25% envelope."""
    envelope = money(money(net_profit) * Decimal('0.25'))
    general = money(envelope * Decimal('0.54'))
    drivers = money(general * Decimal('0.80'))
    mastery = money(envelope * Decimal('0.20'))
    education = money(envelope * Decimal('0.06'))
    return {
        'envelope': envelope, 'general': general, 'drivers': drivers,
        'passengers': general - drivers, 'mastery': mastery, 'education': education,
        'promotion': envelope - general - mastery - education,
    }


def grade_for(personal_pv, left_pv, right_pv):
    return next((grade for grade in reversed(GRADES)
                 if personal_pv >= grade.personal_pv
                 and min(left_pv, right_pv) >= grade.daily_weak_pv), None)


def catalogue():
    return {
        'version': PLAN_VERSION, 'source': 'PLAN COMPENSACION IR CONDUCTORES.pdf',
        'currency': 'COP', 'personal_gate_pv': PERSONAL_GATE,
        'pv_per_cop': '0.001', 'trip_fee_percent': 10,
        'pv_rule_source': 'Confirmación del usuario: viaje de $10.000 genera 10 PV.',
        'distribution': {'net_profit_cap_percent': 25, 'general_percent': 54,
                         'mastery_percent': 20, 'education_percent': 6, 'promotion_percent': 20,
                         'drivers_within_general_percent': 80, 'passengers_within_general_percent': 20},
        'grades': [asdict(item) for item in GRADES],
        'masteries': [asdict(item) for item in MASTERIES],
        'terms': [
            'Comisión general semanal para miembros calificados.',
            'Acumular primero al menos 10.000 PV personales para acumular PV descendentes.',
            'Períodos de maestría: del 1 al 15 y del 16 al último día del mes.',
            'El bono de maestrías se paga cada día 15 y el día 7 después del cierre mensual.',
            'No hay condiciones de mantenimiento continuo de la posición; plazo ilimitado.',
            'No se permite promover dos niveles al mismo tiempo a partir de Gestor Aire (término del PDF).',
            'Para Master Platino, Zafiro, Esmeralda y Diamante: obtener la maestría anterior 3 veces.',
            'Dinero, Tablet y viajes se entregan una sola vez al alcanzar por primera vez cada maestría.',
            'Los productos se basan en el precio de compra.',
            'Avión y hospedaje para Master Bronce/Master Plata: estimado de $2.000.000 por persona.',
            'Avión y hospedaje para Master Zafiro/Master Platino/Master Oro: estimado de $4.000.000 por persona.',
            'Laptop o Tablet: estimado de $3.000.000.',
            'Las cantidades en pesos son estimadas y sujetas a cambios por las reglas del mercado.',
            'El centro de educación recibe dos veces al mes el 6% del fondo del 25%.',
            'La suma de comisiones y bonos no puede exceder el 25% de la utilidad neta de las recargas.',
        ],
        'open_rules': OPEN_RULES,
    }
