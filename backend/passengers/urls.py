from django.urls import path
from .views import LoginView, NearbyPlacesView, PassengerMeView, PlaceDetailsView, PlaceSearchView, RegisterView, RideListCreateView, RouteEstimateView

urlpatterns = [
    path('auth/login/', LoginView.as_view(), name='login'),
    path('auth/register/', RegisterView.as_view(), name='register'),
    path('passenger/me/', PassengerMeView.as_view(), name='passenger-me'),
    path('places/search/', PlaceSearchView.as_view(), name='places-search'),
    path('places/details/', PlaceDetailsView.as_view(), name='places-details'),
    path('places/nearby/', NearbyPlacesView.as_view(), name='places-nearby'),
    path('routes/estimate/', RouteEstimateView.as_view(), name='route-estimate'),
    path('rides/', RideListCreateView.as_view(), name='rides'),
]
