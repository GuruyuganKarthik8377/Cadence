import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/models/profile.dart';

/// The stored `freezes_remaining` is only meaningful inside the month it was
/// last refilled in. The server tops it up on the first spend of a new month
/// (use_freeze, migration 003) — the client can no longer write the column at
/// all — so between the 1st and that first spend, the stored number is last
/// month's leftovers and [Profile.availableFreezes] has to say so.
void main() {
  Profile profileWith({required int remaining, DateTime? refilledOn}) => Profile(
        id: 'u1',
        username: 'me',
        displayName: 'Me',
        freezesRemaining: remaining,
        freezesRefilledOn: refilledOn,
      );

  test('never refilled reads as a full allowance', () {
    expect(
      profileWith(remaining: 0, refilledOn: null).availableFreezes,
      Profile.monthlyFreezes,
    );
  });

  test('an exhausted balance from last month reads as a full allowance', () {
    final now = DateTime.now();
    expect(
      profileWith(
        remaining: 0,
        refilledOn: DateTime(now.year, now.month - 1, 15),
      ).availableFreezes,
      Profile.monthlyFreezes,
    );
  });

  test('same month a year ago is still a different month', () {
    final now = DateTime.now();
    expect(
      profileWith(
        remaining: 0,
        refilledOn: DateTime(now.year - 1, now.month, 1),
      ).availableFreezes,
      Profile.monthlyFreezes,
    );
  });

  test('a balance refilled this month is taken at face value', () {
    final now = DateTime.now();
    expect(
      profileWith(remaining: 1, refilledOn: DateTime(now.year, now.month, 1))
          .availableFreezes,
      1,
    );
  });

  test('spent out this month stays spent out', () {
    final now = DateTime.now();
    expect(
      profileWith(remaining: 0, refilledOn: DateTime(now.year, now.month, 2))
          .availableFreezes,
      0,
    );
  });

  test('fromJson parses the refill date', () {
    final p = Profile.fromJson({
      'id': 'u1',
      'username': 'me',
      'display_name': 'Me',
      'freezes_remaining': 1,
      'freezes_refilled_on': '2026-08-01',
    });
    expect(p.freezesRefilledOn, DateTime(2026, 8, 1));
    expect(p.freezesRemaining, 1);
  });

  test('fromJson tolerates a missing refill date', () {
    final p = Profile.fromJson({
      'id': 'u1',
      'username': 'me',
      'display_name': 'Me',
    });
    expect(p.freezesRefilledOn, isNull);
    expect(p.availableFreezes, Profile.monthlyFreezes);
  });
}
