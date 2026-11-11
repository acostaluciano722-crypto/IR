from django.contrib import admin

from .models import (BinaryPosition, CompensationAward, CompensationBranchCredit, CompensationControl,
                     CompensationFunding, CompensationIncentive, CompensationMember,
                     CompensationPV, CompensationPayout, CompensationPeriod)


class CompensationAuditAdmin(admin.ModelAdmin):
    """Audit only: use transactional operator services for changes."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in (BinaryPosition, CompensationAward, CompensationBranchCredit, CompensationControl,
              CompensationFunding, CompensationIncentive, CompensationMember,
              CompensationPV, CompensationPayout, CompensationPeriod):
    admin.site.register(model, CompensationAuditAdmin)
