# abap-badi-pm-notification-duplicate-check

**Business-rule validation at save time for PM notifications (IW21 / IW22) using BAdI `NOTIF_EVENT_SAVE` - status-aware, type-filtered, and blocking the save through the BAdI's own protocol.**

## Requirement

Maintenance planners were raising a second *breakdown* notification for an equipment while the first one was still open, splitting the history and inflating MTTR statistics. The rule: **for notification type M2, refuse the save if another open M2 notification exists for the same equipment (or functional location when no equipment is given).**

## Design

| Decision | Choice | Reason |
|---|---|---|
| Hook | BAdI `NOTIF_EVENT_SAVE`, method `CHANGE_DATA_AT_SAVE` | Fires once with the complete header (`IS_VIQMEL`) just before the database update, for create *and* change. Upgrade-safe - no user exit `QQMA0014` needed. |
| Filter | `IS_VIQMEL-QMART = 'M2'` as the very first statement | The BAdI fires for every notification type; the rule must cost nothing for the others. |
| "Open" definition | **No active `NOCO` (`I0072`) status in `JEST`** - i.e. `JEST-INACT = ' '` is respected | Status rows are never deleted; a completed-then-reopened notification has an *inactive* NOCO row and must count as open again. |
| Exclude self | `QMNUM <> IS_VIQMEL-QMNUM` | In IW22 the notification being changed would otherwise find itself. |
| Blocking | `EV_SUBRC = 4` + `EV_MSGID/TY/NO/V1..V4` | The framework shows the error and keeps the user in the transaction. An inline `MESSAGE … TYPE 'E'` inside a BAdI would dump or behave differently in background / BAPI contexts. |
| Message | Custom message class `ZPM 001` | *"Open breakdown notification &1 already exists for &2"* - translatable and reusable from other checks. |

See [`zcl_im_notif_dup_check.clas.abap`](zcl_im_notif_dup_check.clas.abap).

## Why `JEST` and not `VIQMEL-STAT`?

`VIQMEL` exposes only the status *text*; the authoritative source is `JEST` keyed by `OBJNR`. Reading `JEST` for the candidate set with `FOR ALL ENTRIES` and treating "no active I0072 row" as *open* is the same logic SAP's own status management uses (`STATUS_CHECK`). Where ABAP Cloud rules apply, replace the two selects with the released views `I_MaintenanceNotification` and `I_MaintNotifSystemStatus` (or a `ZI_` wrapper if those are not available on your release).

## Test cases

| # | Scenario | Expected |
|---|---|---|
| UT-01 | Create M2 for equipment with no other notification | Saved |
| UT-02 | Create M2 for equipment with an open M2 | Blocked, ZPM 001 shows existing number |
| UT-03 | Create M2 for equipment whose earlier M2 is completed (NOCO active) | Saved |
| UT-04 | Earlier M2 completed, then put in process again (NOCO inactive) | Blocked |
| UT-05 | Create M1 (not M2) for equipment with open M2 | Saved - rule not applicable |
| UT-06 | Change existing open M2 in IW22 | Saved - self excluded |
| UT-07 | No equipment, functional location only, open M2 on same FL | Blocked |

## Activation

SE19 → new BAdI (enhancement spot `BADI_NOTIF_EVENT_SAVE`) or classic BAdI `NOTIF_EVENT_SAVE` depending on release → implementing class from this repo → activate. No configuration change required.

---
*Written as generic reference material. No client data or client-specific logic.* MIT License - see [LICENSE](LICENSE).
