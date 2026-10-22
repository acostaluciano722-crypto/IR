from django.urls import path
from .views import DriverMeView, DriverPresenceView, DriverWalletTransactionsView, DriverAvailableRidesView, DriverRidesView, RideOfferAcceptView, RideOfferCreateView, RideRejectView, RideUpdateStatusView, RideVerifyPickupCodeView, WalletRechargeView

urlpatterns = [
    path('me/', DriverMeView.as_view(), name='driver-me'),
    path('presence/', DriverPresenceView.as_view(), name='driver-presence'),
    path('nearby/', DriverPresenceView.as_view(), name='nearby-drivers'),
    path('rides/available/', DriverAvailableRidesView.as_view(), name='driver-available-rides'),
    path('rides/mine/', DriverRidesView.as_view(), name='driver-rides'),
    path('rides/<int:ride_id>/offers/', RideOfferCreateView.as_view(), name='driver-ride-offers'),
    path('rides/<int:ride_id>/accept/', RideOfferAcceptView.as_view(), name='driver-ride-accept'),
    path('rides/<int:ride_id>/reject/', RideRejectView.as_view(), name='driver-ride-reject'),
    path('rides/<int:ride_id>/status/', RideUpdateStatusView.as_view(), name='driver-ride-status'),
    path('rides/<int:ride_id>/verify-code/', RideVerifyPickupCodeView.as_view(), name='driver-ride-verify-code'),
    path('wallet/recharge/', WalletRechargeView.as_view(), name='driver-wallet-recharge'),
    path('wallet/transactions/', DriverWalletTransactionsView.as_view(), name='driver-wallet-transactions'),
]

