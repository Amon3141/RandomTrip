from django.urls import path
from . import views

app_name = 'notes'

urlpatterns = [
  path('', views.randomtrip, name='randomtrip'),
]