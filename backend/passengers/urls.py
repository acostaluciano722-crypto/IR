from django.urls import path
from .views import LoginView, NearbyPlacesView, PassengerMeView, PlaceDetailsView, PlaceSearchView, RegisterView, RideCancelView, RideListCreateView, RideLocationView, RideOfferRejectView, RideOfferSelectView, RideRatingView, RouteEstimateView

urlpatterns = [
    path('auth/login/', LoginView.as_view(), name='login'),
    path('auth/register/', RegisterView.as_view(), name='register'),
    path('passenger/me/', PassengerMeView.as_view(), name='passenger-me'),
    path('places/search/', PlaceSearchView.as_view(), name='places-search'),
    path('places/details/', PlaceDetailsView.as_view(), name='places-details'),
    path('places/nearby/', NearbyPlacesView.as_view(), name='places-nearby'),
    path('routes/estimate/', RouteEstimateView.as_view(), name='route-estimate'),
    path('rides/', RideListCreateView.as_view(), name='rides'),
    path('rides/<int:ride_id>/offers/<int:offer_id>/select/', RideOfferSelectView.as_view(), name='select-ride-offer'),
    path('rides/<int:ride_id>/offers/<int:offer_id>/reject/', RideOfferRejectView.as_view(), name='reject-ride-offer'),
    path('rides/<int:ride_id>/location/', RideLocationView.as_view(), name='ride-location'),
    path('rides/<int:ride_id>/cancel/', RideCancelView.as_view(), name='cancel-ride'),
    path('rides/<int:ride_id>/rating/', RideRatingView.as_view(), name='ride-rating'),
]
