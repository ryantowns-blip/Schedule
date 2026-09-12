import 'package:atc_schedule_manager/models/leave_balance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = LeaveProjectionService();

  test('projects accrual and deduplicates leave on the same date', () {
    final settings = LeaveBalanceSettings(
      effectiveDate: DateTime(2026, 9, 12),
      annualBalance: 220,
      sickBalance: 100,
      annualAccrualPerPayPeriod: 8,
      sickAccrualPerPayPeriod: 4,
    );
    final projection = service.calculate(
      settings: settings,
      usage: [
        LeaveUsage(date: DateTime(2026, 10, 1), kind: LeaveKind.annual),
        LeaveUsage(date: DateTime(2026, 10, 1), kind: LeaveKind.annual),
        LeaveUsage(date: DateTime(2026, 11, 2), kind: LeaveKind.sick),
      ],
    );

    expect(projection.annualPlanned, 8);
    expect(projection.sickPlanned, 8);
    expect(projection.remainingPayPeriods, greaterThan(0));
    expect(projection.projectedAnnual, 220 + projection.annualAccrued - 8);
    expect(projection.projectedSick, 100 + projection.sickAccrued - 8);
  });

  test('six hour category receives ten hours in final pay period', () {
    final settings = LeaveBalanceSettings(
      effectiveDate: DateTime(2026, 12, 26),
      annualBalance: 0,
      sickBalance: 0,
      annualAccrualPerPayPeriod: 6,
      sickAccrualPerPayPeriod: 4,
    );
    final projection = service.calculate(settings: settings, usage: const []);
    expect(projection.annualAccrued, 10);
  });

  test('reports use or lose above carryover limit', () {
    final settings = LeaveBalanceSettings(
      effectiveDate: DateTime(2026, 12, 26),
      annualBalance: 250,
      sickBalance: 0,
      annualAccrualPerPayPeriod: 8,
      sickAccrualPerPayPeriod: 4,
      annualCarryoverLimit: 240,
    );
    final projection = service.calculate(settings: settings, usage: const []);
    expect(projection.useOrLose, projection.projectedAnnual - 240);
  });

  test('manual entries with unique ids are counted separately', () {
    final settings = LeaveBalanceSettings(
      effectiveDate: DateTime(2026, 9, 12),
      annualBalance: 100,
      sickBalance: 100,
      annualAccrualPerPayPeriod: 0,
      sickAccrualPerPayPeriod: 0,
    );
    final projection = service.calculate(
      settings: settings,
      usage: [
        LeaveUsage(id: 'manual-1', date: DateTime(2026, 10, 1), kind: LeaveKind.annual, hours: 2),
        LeaveUsage(id: 'manual-2', date: DateTime(2026, 10, 1), kind: LeaveKind.annual, hours: 3),
      ],
    );
    expect(projection.annualPlanned, 5);
    expect(projection.projectedAnnual, 95);
  });
  test('counts manual leave used on the starting balance date', () {
    final settings = LeaveBalanceSettings(
      effectiveDate: DateTime(2026, 9, 12),
      annualBalance: 100,
      sickBalance: 80,
      annualAccrualPerPayPeriod: 0,
      sickAccrualPerPayPeriod: 0,
    );
    final projection = service.calculate(
      settings: settings,
      usage: [
        LeaveUsage(
          id: 'manual-same-day',
          date: DateTime(2026, 9, 12),
          kind: LeaveKind.annual,
          hours: 4,
        ),
      ],
    );
    expect(projection.annualPlanned, 4);
    expect(projection.currentAnnual, 96);
    expect(projection.projectedAnnual, 96);
  });
  test('counts prior manual leave within the current leave year', () {
    final settings = LeaveBalanceSettings(
      effectiveDate: DateTime(2026, 9, 12),
      annualBalance: 120,
      sickBalance: 20,
      annualAccrualPerPayPeriod: 0,
      sickAccrualPerPayPeriod: 0,
    );
    final projection = service.calculate(
      settings: settings,
      usage: [
        LeaveUsage(
          id: 'manual-prior-date',
          date: DateTime(2026, 9, 8),
          kind: LeaveKind.annual,
          hours: 2,
        ),
        LeaveUsage(
          date: DateTime(2026, 9, 8),
          kind: LeaveKind.annual,
          hours: 8,
        ),
      ],
    );
    expect(projection.annualPlanned, 2);
    expect(projection.currentAnnual, 118);
    expect(projection.projectedAnnual, 118);
  });
}
