class NHDACrowbar : HDCoreBaseMeleeWeapon {

	const CROWBAR_RANGE = 72;
	const CROWBAR_RANGE_SQUARED = CROWBAR_RANGE ** 2;

	private bool attached;

	double charge;

	private Sector blockedSector;
	private bool blockedSectorWasSilent;

	default {
		+NOBLOOD
		+NODAMAGE
		
		scale 0.75;
		radius 12;
		height 4;
		
		health TELEFRAG_DAMAGE;
		painchance 256;
		
		+SpriteAngle
		SpriteAngle 180;

		obituary "$OB_CROWBAR"; 
		weapon.kickback 120;
		weapon.slotpriority 0.2;
		inventory.pickupmessage "$PICKUP_CROWBAR";
		tag "$TAG_CROWBAR";
		hdweapon.refid HDLD_CROWBAR;

		damage                              50;
		damageType                          'bashing';
		meleeRange                          64.0;
		HDCoreBaseMeleeWeapon.attackFlags   HDCMW_DO_HEADSHOT|HDCMW_DO_PUFF|HDCMW_DO_WALLBUST|HDCMW_DO_WINDOWBUST|HDCMW_RECOIL_ATTACKEE;
	}

	override bool CanCollideWith(Actor other, bool passive) { return super.CanCollideWith(other, passive) || (bSHOOTABLE && other.bMISSILE); }

	override double WeaponBulk() { return 64; }

	override double GunMass() { return 12; }

	override string, double GetPickupSprite() { return "CBARA0", 1.0; }

	override string GetHelpText() {
		LocalizeHelp();

		return WEPHELP_FIRE..StringTable.Localize("$CROWBARWH_FIRE")
		..WEPHELP_ALTFIRE..StringTable.Localize("$CROWBARWH_ALTFIRE")
		..WEPHELP_RELOAD..StringTable.Localize("$CROWBARWH_RELOAD")
		..WEPHELP_UNLOAD..StringTable.Localize("$CROWBARWH_UNLOAD")
		;
	}

	void AttachCrowbar(Sector blocked, bool onFloor) {
		if (attached) return;
		attached = true;

		if (blocked) {
			blockedSector = blocked;

			// selected plane has sector effect thinker
			if (
				(onFloor && blocked.floordata)
				|| (!onFloor && blocked.ceilingdata)
			) {
				blockedSectorWasSilent = blocked.flags & Sector.SECF_SILENTMOVE;
				if (!blockedSectorWasSilent) blocked.flags |= Sector.SECF_SILENTMOVE;
			}
		}

		spriteAngle = onFloor ? 0 : 225;

		bNOGRAVITY = bWALLSPRITE = bACTLIKEBRIDGE = bSHOOTABLE = true;

		// do not the dragging
		mass = int.MAX;
	}

	void DetachCrowbar() {
		if (!attached) return;
		attached = false;

		if (blockedSector) {
			if (!blockedSectorWasSilent) blockedSector.flags &= ~Sector.SECF_SILENTMOVE;

			blockedSector = null;
		}

		spriteAngle = 180;

		bNOGRAVITY = bWALLSPRITE = bACTLIKEBRIDGE = bSHOOTABLE = false;

		mass = default.mass;
	}

	override void ActualPickup(Actor other, bool silent) {
		super.ActualPickup(other, silent);

		DetachCrowbar();
	}

	override void OnDestroy() {
		super.OnDestroy();

		DetachCrowbar();
	}

	void CrowbarJam(FLineTraceData data) {
		Sector blocked;
		Vector3 newPos;
		bool place = false;
		bool onFloor = false;

		double newAngle;

		switch(data.HitType) {
			case Trace_HitWall:
				blocked = data.HitSector;

				let hitLine = data.HitLine;

				let delta = hitLine.delta;
				if (data.LineSide == Line.FRONT) delta = -delta;

				let hitNormal = (-delta.y, delta.x).Unit();

				newPos = data.HitLocation + (hitNormal * radius * 1.3);
				newAngle = VectorAngle(hitNormal.x, hitNormal.y) - 90;

				let blockedFloorZ = blocked.floorPlane.ZAtPoint(data.HitLocation.xy);
				let blockedCeilZ = blocked.ceilingPlane.ZAtPoint(data.HitLocation.xy);

				let blockedHeight = blockedCeilZ - blockedFloorZ;

				if (newPos.z >= min(blockedCeilZ, (blockedHeight * 0.7) + blockedFloorZ)) {
					newPos.z = blockedCeilZ - height;
					place = true;
				} else if (newPos.z <= max(blockedFloorZ, (blockedHeight * 0.3) + blockedFloorZ)) {
					newPos.z = blockedFloorZ;
					onFloor = true;
					place = true;
				}

				break;

			case Trace_HitCeiling:
			case Trace_HitFloor:
				blocked = data.HitSector;
				onFloor = data.HitType == Trace_HitFloor;

				if (onFloor ? blocked.floorPlane.isSlope() : blocked.ceilingPlane.isSlope()) break;

				let hitPos = data.HitLocation;

				let nearestLine = -1;
				let nearestDist = Double.INFINITY;
				let nearestVert = (0, 0);

				// find nearest line
				for (int i = 0; i < blocked.lines.Size(); i++) {
					let lll = blocked.lines[ i ];
					let other = lll.frontsector == blocked ? lll.backsector : lll.frontsector;
					if (other == blocked) continue;

					// math...........................
					let delta = lll.delta;
					let fact = (delta dot (hitPos.xy - lll.v1.p)) / (delta dot delta);
					let nearVert = lll.v1.p + delta * fact;

					let blockedFloorZ = blocked.floorPlane.ZAtPoint(nearVert);
					let blockedCeilZ = blocked.ceilingPlane.ZAtPoint(nearVert);

					let otherFloorZ = Double.INFINITY;
					let otherCeilZ = -Double.INFINITY;

					if (other) {
						otherFloorZ = other.floorPlane.ZAtPoint(nearVert);
						otherCeilZ = other.ceilingPlane.ZAtPoint(nearVert);
					}

					if (onFloor
						? (blockedFloorZ < otherFloorZ || blockedFloorZ > otherCeilZ)
						: (blockedCeilZ  > otherCeilZ  || blockedCeilZ < otherFloorZ)
					) {
						delta = nearVert - hitPos.xy;
						let nearDist = delta dot delta;

						if (nearDist < nearestDist)
						{
							nearestLine = i;
							nearestDist = nearDist;
							nearestVert = nearVert;
						}
					}
				}

				if (nearestLine < 0 || nearestDist > CROWBAR_RANGE_SQUARED) break;

				let lll = blocked.lines[ nearestLine ];

				delta = lll.delta;
				if (lll.frontsector == blocked)
					delta = -delta;

				hitNormal = (-delta.y, delta.x).Unit();

				newAngle = VectorAngle(hitNormal.x, hitNormal.y) - 90;
				newPos.xy = nearestVert + (hitNormal * radius * 1.3);

				if (onFloor) {
					newPos.z = blocked.floorPlane.ZAtPoint(nearestVert);
				} else {
					newPos.z = blocked.ceilingPlane.ZAtPoint(nearestVert) - height;
				}

				place = true;

				break;

			case Trace_HitNone:
			default:
				break;
		}

		if (place) {
			let cbr = NHDACrowbar(Spawn("NHDACrowbar", newPos));

			if (owner.Distance3DSquared(cbr) <= CROWBAR_RANGE_SQUARED) {
				cbr.angle = newAngle;
				cbr.AttachCrowbar(blocked, onFloor);

				amount -= 1;
				GetSpareWeapon(owner);
			} else {
				cbr.Destroy();
			}
		}
	}

	override double GetWeaponDamage() {
		return super.getWeaponDamage() + (3 * charge);
	}

	override bool getWeaponLeftHanded() {
		return false;
	}

	override void doWallBust(double dist, double dmg) {
		super.doWallBust(dist, dmg * strength * 0.2);

		owner.A_StartSound("crowbar/hitwall", CHAN_AUTO);
		owner.A_Recoil((dmg * 0.02) + 1);
	}

	override void doWindowBust(FLineTraceData atkLine, double dmg) {
		DoorDestroyer.CheckDirtyWindowBreak(atkLine.hitLine, 0.09 + (strength * 0.03), atkLine.hitLocation);
	}

	states {
		select0:
			CRWB A 0;
			goto select0small;

		deselect0:
			CRWB A 0;
			goto deselect0small;

		ready:
			#### A 1 {
				if (
					invoker.wasHolding
					&& player.cmd.buttons&(
						BT_ATTACK
						|BT_ALTATTACK
						|BT_RELOAD
						|BT_ZOOM
						|BT_USER1
						|BT_USER2
						|BT_USER3
						|BT_USER4
					)
				) {
					setWeaponState("nope");
					return;
				}

				A_WeaponReady(WRF_ALL);
				invoker.flicked = invoker.wasHolding = false;
			}
			goto readyend;

		reload:
			#### A 0 A_JumpIf(HDPlayerPawn(self).stunned > 0, "nope");
		flick:
			#### B 1 offset(0, 50);
			#### C 1 offset(0, 36);
			#### DDDDDD 0 A_CustomPunch((int(ceil(invoker.strength))), 1, CPF_PULLIN, "HDFistPuncher", 36);
			#### DD 1 offset(0, 38) {
				invoker.flicked = true;
			}
			#### C 1 offset(0, 42);
			#### B 1 offset(0, 50);
			goto fire;

		fire:
			#### A 0 A_JumpIf(HDPlayerPawn(self).stunned > 0, "nope");
		swing:
			CRWB BBCD 1;//faster prep
		swinghold:
			TNT1 A 1 {
				let hdp = HDPlayerPawn(self);

				//holding the crowbar ready tires you
				if (!random(0, 99)) hdp.fatigue++;
				invoker.charge = min(10, (invoker.charge + 1) * 0.333);
			
				//aborts swing if stunned or tired
				if (hdp.fatigue > HDCONST_SPRINTFATIGUE) {
					A_PlaySkinSound(SKINSOUND_GRUNT, "*usefail");
					setWeaponState("swing_end");

					return;
				}
			}
			TNT1 A 0 A_JumpIf(PressingFire()||PressingAltFire()||PressingReload(), "swinghold" );
			CRWB EFGHI 1;
			CRWB J 1 {
				A_StartSound("crowbar/swing", CHAN_WEAPON);
				if (invoker.charge >= 8) A_StartSound("crowbar/crit", 9);

				// swinging the crowbar exhausts your stamina,
				// heavy swings are more tiring than light swings
				HDPlayerPawn(self).fatigue += 1 + (invoker.charge * 0.5);
			}
			CRWB KL 1;
			CRWB M 1 A_MeleeWeaponAttack();
			CRWB NOP 1;
			TNT1 A 6 A_JumpIf(invoker.zerk, 1); // faster swings if zerked
			TNT1 A 2 {
				invoker.charge = 0; 
				if (PressingFire()) setWeaponState("swinghold");
			}
		swing_end:
			CRWB DDCB 1; // faster recovery
			#### A 0 A_JumpIf(PressingFire(), "nope");
			goto ready;

		altfire:
			#### A 0 A_JumpIf(HDPlayerPawn(self).stunned > 0, "nope");
		bodycheck:
			#### A 3 A_Lunge(
				HDPlayerPawn(self).strength * (invoker.zerk ? 8 : 6) / max(1.0, HDPlayerPawn(self).overloaded),
				fatigueIncr: 4,
				abortState: 'swing'
			);
			CRWB BCD 1;
			goto swinghold;
		
		// two-handed weapon, can't grab
		firemode:
			goto nope;
		
		unload:
		place:
			CRWB BCD 2;
		placehold:
			TNT1 A 1 A_WeaponBusy;
			TNT1 A 0 A_JumpIf(PressingUnload(), "placehold");
			TNT1 A 0 {
				FLineTraceData data;
				linetrace(
					angle,
					CROWBAR_RANGE,
					pitch,
					flags: 0,
					offsetz: invoker.getWeaponAttackHeight(),
					data: data
				);

				invoker.CrowbarJam(data);
			}
			CRWB DCB 2;
			goto nope;

		spawn:
			CBAR A -1;
			stop;

		pain:
		crush:
			CBAR A 0 {
				if (invoker.attached) {
					// TODO: better pain sound
					invoker.A_StartSound("crowbar/hitwall");

					invoker.DetachCrowbar();
				}
			}
			goto spawn;
	}
}
