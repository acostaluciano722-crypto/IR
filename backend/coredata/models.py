from django.contrib.auth.hashers import check_password
from django.db import models


class ExternalTable(models.Model):
    class Meta:
        abstract = True
        managed = False


class Usuario(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_usuario')
    nombres = models.CharField(max_length=100, null=True, blank=True)
    apellidos = models.CharField(max_length=100, null=True, blank=True)
    correo = models.CharField(max_length=255, unique=True, null=True, blank=True)
    celular = models.CharField(max_length=20, null=True, blank=True)
    contrasena_hash = models.CharField(max_length=255, null=True, blank=True)
    rol = models.CharField(max_length=20, null=True, blank=True)
    estado = models.CharField(max_length=20, null=True, blank=True)
    fecha_creacion = models.DateTimeField(null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'usuario'

    @property
    def username(self):
        return self.correo or ''

    @property
    def is_authenticated(self):
        return True

    @property
    def is_anonymous(self):
        return False

    def get_full_name(self):
        return ' '.join(part for part in (self.nombres, self.apellidos) if part).strip()

    def check_password(self, raw_password):
        return check_password(raw_password, self.contrasena_hash or '')

    def __str__(self):
        return self.get_full_name() or self.username


class Rango(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_rango')
    nombre = models.CharField(max_length=30, db_column='nombre_rango', null=True, blank=True)
    bono_multiplicador = models.DecimalField(max_digits=3, decimal_places=2, null=True, blank=True)
    pi_minimos = models.IntegerField(null=True, blank=True)
    pg_i_minimos = models.IntegerField(null=True, blank=True)
    pg_d_minimos = models.IntegerField(null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'rangos'


class ZonaGeografica(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_zona')
    nombre = models.CharField(max_length=50, db_column='nombre_zona', null=True, blank=True)
    estado = models.CharField(max_length=20, null=True, blank=True)
    tipo_zona = models.CharField(max_length=50, null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'zona_geografica'


class Tarifa(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_tarifa')
    zona_origen = models.ForeignKey(ZonaGeografica, models.DO_NOTHING, db_column='id_zona_origen', null=True, blank=True, related_name='tarifas_origen')
    zona_destino = models.ForeignKey(ZonaGeografica, models.DO_NOTHING, db_column='id_zona_destino', null=True, blank=True, related_name='tarifas_destino')
    precio_base_legal = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    vigencia_ano = models.IntegerField(null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'tarifa'


class PassengerProfile(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_pasajero')
    user = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_usuario', null=True, blank=True, related_name='passenger_profiles')
    rating = models.DecimalField(max_digits=3, decimal_places=2, db_column='calificacion_promedio', null=True, blank=True)
    default_payment = models.CharField(max_length=30, db_column='califi_pago_defecto', null=True, blank=True)
    total_rides = models.IntegerField(db_column='viajes_completados', null=True, blank=True)
    points = models.IntegerField(db_column='puntos_pa', null=True, blank=True)
    rank = models.ForeignKey(Rango, models.DO_NOTHING, db_column='id_rango', null=True, blank=True)
    points_left = models.IntegerField(db_column='puntos_pa_i', null=True, blank=True)
    points_right = models.IntegerField(db_column='puntos_pa_d', null=True, blank=True)
    bonus_balance = models.DecimalField(max_digits=10, decimal_places=2, db_column='saldo_bonos_disponible', null=True, blank=True)
    sponsor = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_sponsor_p', null=True, blank=True, related_name='sponsored_passengers')
    ancestor = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_ancestro_estructural_p', null=True, blank=True, related_name='passenger_descendants')
    network_side = models.CharField(max_length=20, db_column='lado_red_p', null=True, blank=True)
    rating_count = models.IntegerField(db_column='cantidad_calificaciones', default=0)

    class Meta(ExternalTable.Meta):
        db_table = 'perfil_pasajero'


class DriverProfile(ExternalTable):
    class Status(models.TextChoices):
        OFFLINE = 'offline', 'Desconectado'
        AVAILABLE = 'available', 'Disponible'
        RESERVED_FOR_TRIP = 'reserved_for_trip', 'Reservado para viaje'
        EN_ROUTE = 'en_route', 'En ruta'
        ARRIVED = 'arrived', 'Llegó'
        IN_TRIP = 'in_trip', 'En viaje'
        RESTRICTED = 'restricted', 'Restringido'

    id = models.UUIDField(primary_key=True, db_column='id_conductor')
    user = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_usuario', null=True, blank=True, related_name='driver_profiles')
    status = models.CharField(max_length=20, db_column='estado_cuenta', null=True, blank=True)
    document_number = models.CharField(max_length=20, db_column='doc_identidad', null=True, blank=True)
    total_rides = models.IntegerField(db_column='viajes_completados', null=True, blank=True)
    rating = models.DecimalField(max_digits=3, decimal_places=2, db_column='calificacion_promedio', null=True, blank=True)
    points = models.IntegerField(db_column='puntos_co', null=True, blank=True)
    rank = models.ForeignKey(Rango, models.DO_NOTHING, db_column='id_rango', null=True, blank=True)
    points_left = models.IntegerField(db_column='puntos_co_i', null=True, blank=True)
    points_right = models.IntegerField(db_column='puntos_co_d', null=True, blank=True)
    wallet_balance = models.DecimalField(max_digits=10, decimal_places=2, db_column='saldo_bolsa_disponible', null=True, blank=True)
    reserved_balance = models.DecimalField(max_digits=10, decimal_places=2, db_column='saldo_bolsa_reservado', null=True, blank=True)
    bonus_balance = models.DecimalField(max_digits=10, decimal_places=2, db_column='saldo_bonos_disponible', null=True, blank=True)
    sponsor = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_sponsor', null=True, blank=True, related_name='sponsored_drivers')
    ancestor = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_ancestro_estructural', null=True, blank=True, related_name='driver_descendants')
    network_side = models.CharField(max_length=20, db_column='lado_red', null=True, blank=True)
    rating_count = models.IntegerField(db_column='cantidad_calificaciones', default=0)

    class Meta(ExternalTable.Meta):
        db_table = 'perfil_conductor'

    @property
    def available_balance(self):
        return (self.wallet_balance or 0) - (self.reserved_balance or 0)

    @property
    def tier(self):
        return self.rank.nombre if self.rank_id else 'Inicial'


class Vehicle(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_vehiculo')
    driver = models.ForeignKey(DriverProfile, models.DO_NOTHING, db_column='id_conductor', null=True, blank=True, related_name='vehicles')
    plate = models.CharField(max_length=10, db_column='placa', null=True, blank=True)
    brand_model = models.CharField(max_length=100, db_column='marca_modelo', null=True, blank=True)
    category = models.CharField(max_length=30, db_column='categoria', null=True, blank=True)
    color = models.CharField(max_length=30, null=True, blank=True)
    status = models.CharField(max_length=20, db_column='estado_vehiculo', null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'vehiculo'


class DriverDocument(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_documento')
    driver = models.ForeignKey(DriverProfile, models.DO_NOTHING, db_column='id_conductor', null=True, blank=True)
    document_type = models.CharField(max_length=50, db_column='tipo_documento', null=True, blank=True)
    file_url = models.CharField(max_length=500, db_column='url_archivo', null=True, blank=True)
    validation_status = models.CharField(max_length=20, db_column='estado_validacion', null=True, blank=True)
    expires_at = models.DateField(db_column='fecha_vencimiento', null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'documentos'


class Ride(ExternalTable):
    class Status(models.TextChoices):
        SEARCHING = 'searching', 'Buscando conductor'
        REQUESTED = 'requested', 'Solicitado'
        NEGOTIATING = 'negotiating', 'Negociando'
        ACCEPTED = 'accepted', 'Aceptado'
        DRIVER_SELECTED = 'driver_selected', 'Conductor seleccionado'
        EN_ROUTE = 'en_route', 'En ruta'
        ARRIVED = 'arrived', 'Llegó'
        IN_PROGRESS = 'in_progress', 'En progreso'
        COMPLETED = 'completed', 'Completado'
        VALIDATED = 'validated', 'Validado'
        CANCELLED = 'cancelled', 'Cancelado'

    id = models.UUIDField(primary_key=True, db_column='id_viaje')
    passenger_profile = models.ForeignKey(PassengerProfile, models.DO_NOTHING, db_column='id_pasajero', null=True, blank=True, related_name='rides')
    driver_profile = models.ForeignKey(DriverProfile, models.DO_NOTHING, db_column='id_conductor', null=True, blank=True, related_name='rides')
    origin_zone = models.ForeignKey(ZonaGeografica, models.DO_NOTHING, db_column='id_zona_origen', null=True, blank=True, related_name='rides_origin')
    destination_zone = models.ForeignKey(ZonaGeografica, models.DO_NOTHING, db_column='id_zona_destino', null=True, blank=True, related_name='rides_destination')
    final_fare = models.DecimalField(max_digits=10, decimal_places=2, db_column='precio_final', null=True, blank=True)
    status = models.CharField(max_length=20, db_column='estado_viaje', null=True, blank=True)
    created_at = models.DateTimeField(db_column='fecha_solicitud', null=True, blank=True)
    distance_meters = models.IntegerField(db_column='distancia_metros', null=True, blank=True)
    duration_seconds = models.IntegerField(db_column='tiempo_segundos', null=True, blank=True)
    estimated_price = models.DecimalField(max_digits=10, decimal_places=2, db_column='tarifa_recomendada', null=True, blank=True)
    reserved_debit = models.DecimalField(max_digits=10, decimal_places=2, db_column='debito_bolsa_reservado', null=True, blank=True)
    pickup_code = models.CharField(max_length=20, db_column='pin_seguridad', null=True, blank=True)
    payment_method = models.CharField(max_length=50, db_column='metodo_pago', null=True, blank=True)
    origin = models.CharField(max_length=255, db_column='origen_direccion', null=True, blank=True)
    destination = models.CharField(max_length=255, db_column='destino_direccion', null=True, blank=True)
    vehicle_type = models.CharField(max_length=30, db_column='tipo_vehiculo', default='economy')
    offer_amount = models.DecimalField(max_digits=10, decimal_places=2, db_column='oferta_inicial', default=0)
    passenger_rating = models.PositiveSmallIntegerField(db_column='calificacion_pasajero', null=True, blank=True)
    driver_rating = models.PositiveSmallIntegerField(db_column='calificacion_conductor', null=True, blank=True)
    passenger_location_label = models.CharField(max_length=255, db_column='etiqueta_pasajero', blank=True, default='')
    driver_location_label = models.CharField(max_length=255, db_column='etiqueta_conductor', blank=True, default='')

    class Meta(ExternalTable.Meta):
        db_table = 'viaje'
        ordering = ['-created_at']


class RideOffer(ExternalTable):
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pendiente'
        ACCEPTED = 'accepted', 'Aceptada'
        REJECTED = 'rejected', 'Rechazada'

    id = models.UUIDField(primary_key=True, db_column='id_oferta')
    ride = models.ForeignKey(Ride, models.DO_NOTHING, db_column='id_viaje', null=True, blank=True, related_name='offers')
    driver_profile = models.ForeignKey(DriverProfile, models.DO_NOTHING, db_column='id_conductor', null=True, blank=True, related_name='offers')
    amount = models.DecimalField(max_digits=10, decimal_places=2, db_column='precio_propuesto', null=True, blank=True)
    status = models.CharField(max_length=20, db_column='estado_oferta', null=True, blank=True)
    created_at = models.DateTimeField(db_column='fecha_oferta', null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'ofertas'


class DriverTransaction(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_transaccion')
    driver_profile = models.ForeignKey(DriverProfile, models.DO_NOTHING, db_column='id_conductor', null=True, blank=True)
    ride = models.ForeignKey(Ride, models.DO_NOTHING, db_column='id_viaje', null=True, blank=True)
    amount = models.DecimalField(max_digits=10, decimal_places=2, db_column='monto', null=True, blank=True)
    movement_type = models.CharField(max_length=30, db_column='tipo_movimiento', null=True, blank=True)
    payment_reference = models.CharField(max_length=100, db_column='referencia_wompi', null=True, blank=True)
    created_at = models.DateTimeField(db_column='fecha_transaccion', null=True, blank=True)
    status = models.CharField(max_length=20, db_column='estado_transaccion', null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'transacciones'


class PointHistory(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_historial')
    user = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_usuario', null=True, blank=True)
    ride = models.ForeignKey(Ride, models.DO_NOTHING, db_column='id_viaje', null=True, blank=True)
    amount = models.IntegerField(db_column='cantidad_puntos', null=True, blank=True)
    reason = models.CharField(max_length=50, db_column='motivo', null=True, blank=True)
    created_at = models.DateTimeField(db_column='fecha_registro', null=True, blank=True)
    network_role = models.CharField(max_length=20, db_column='rol_red', null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'historial_puntos'


class SupportTicket(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_ticket')
    user = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_usuario', null=True, blank=True)
    ride = models.ForeignKey(Ride, models.DO_NOTHING, db_column='id_viaje', null=True, blank=True)
    issue_type = models.CharField(max_length=50, db_column='tipo_incidencia', null=True, blank=True)
    description = models.TextField(null=True, blank=True)
    status = models.CharField(max_length=20, db_column='estado_ticket', null=True, blank=True)
    created_at = models.DateTimeField(db_column='fecha_apertura', null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'tickets_de_soporte'


class BonusWithdrawal(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_retiro')
    user = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_usuario', null=True, blank=True)
    amount = models.DecimalField(max_digits=10, decimal_places=2, db_column='monto_solicitado', null=True, blank=True)
    payment_method = models.CharField(max_length=50, db_column='metodo_pago_destino', null=True, blank=True)
    status = models.CharField(max_length=20, db_column='estado_retiro', null=True, blank=True)
    created_at = models.DateTimeField(db_column='fecha_solicitud', null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'retiro_bonificacion'


class UserBonus(ExternalTable):
    id = models.UUIDField(primary_key=True, db_column='id_bono')
    user = models.ForeignKey(Usuario, models.DO_NOTHING, db_column='id_usuario', null=True, blank=True)
    network_role = models.CharField(max_length=20, db_column='rol_red', null=True, blank=True)
    reason = models.CharField(max_length=50, db_column='motivo_bono', null=True, blank=True)
    generated_points = models.IntegerField(db_column='up_generadas', null=True, blank=True)
    liquidated_amount = models.DecimalField(max_digits=10, decimal_places=2, db_column='monto_liquidado', null=True, blank=True)
    status = models.CharField(max_length=20, db_column='estado_bono', null=True, blank=True)
    closed_at = models.DateTimeField(db_column='fecha_cierre', null=True, blank=True)

    class Meta(ExternalTable.Meta):
        db_table = 'bonificacion_usuario'