// Roles of the people sharing a building, and what each may do.
//
//   owner  created the building (one, immutable); can do everything
//   admin  a co-owner: everything, except changing the owner's membership
//   mod    runs the day to day (rooms, leases, rents, expenses); can invite
//          and revoke tenants and workers only
//   user   a tenant: sees only the building, their own lease and payments
//          and who manages it; changes only their own contact details and
//          documents
//   worker does work in the building (cleaning...): sees only the tasks
//          given to them and who manages it; marks tasks done with photos
//
// Rows written before roles existed say 'member': they act as mods.

enum Role { owner, admin, mod, user, worker }

Role? roleOf(Object? s) => switch (s) {
      'owner' => Role.owner,
      'admin' => Role.admin,
      'mod' || 'member' => Role.mod,
      'user' => Role.user,
      'worker' => Role.worker,
      _ => null,
    };

extension RoleRules on Role {
  /// Sees and changes all of the building's data.
  bool get isStaff => this == Role.owner || this == Role.admin || this == Role.mod;

  /// Receives only the rows about themselves (see SyncEngine.scopeFor).
  bool get isPartial => !isStaff;

  /// May write rows of [entity] without restriction (`members`, `profiles`
  /// and the partial roles' own rows are judged separately).
  bool canWrite(String entity) => isStaff;

  /// May delete the building itself.
  bool get canDeleteBuilding => this == Role.owner || this == Role.admin;

  /// May give tasks to workers and approve their work.
  bool get canReviewTasks => isStaff;

  /// Roles this role may hand out with an invite or a role change.
  List<Role> get canGrant => switch (this) {
        Role.owner || Role.admin => const [Role.admin, Role.mod, Role.user, Role.worker],
        Role.mod => const [Role.user, Role.worker],
        Role.user || Role.worker => const [],
      };

  /// May change or revoke the membership of someone whose role is [target]
  /// (null: no membership yet), giving them [to] (null: role unchanged).
  bool canManage(Role? target, Role? to) {
    if (target == Role.owner || to == Role.owner) return false;
    final grant = canGrant;
    if (grant.isEmpty) return false;
    if (target != null && !grant.contains(target)) return false;
    if (to != null && !grant.contains(to)) return false;
    return true;
  }
}
