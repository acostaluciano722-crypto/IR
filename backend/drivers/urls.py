from django.urls import path
from .views import DriverMeView, DriverAvailableRidesView, DriverRidesView, RideOfferCreateView, RideUpdateStatusView, WalletRechargeView

urlpatterns = [
    path('me/', DriverMeView.as_view(), name='driver-me'),
    path('rides/available/', DriverAvailableRidesView.as_view(), name='driver-available-rides'),
    path('rides/mine/', DriverRidesView.as_view(), name='driver-rides'),
    path('rides/<int:ride_id>/offers/', RideOfferCreateView.as_view(), name='driver-ride-offers'),
    path('rides/<int:ride_id>/status/', RideUpdateStatusView.as_view(), name='driver-ride-status'),
    path('wallet/recharge/', WalletRechargeView.as_view(), name='driver-wallet-recharge'),
]

