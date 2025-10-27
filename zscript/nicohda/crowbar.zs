class NHDACrowbar : HDWeapon
{
	const CrowbarRange = 72;
	const CrowbarRangeSqr = CrowbarRange ** 2;

	default
	{
		inventory.pickupmessage "You got the crowbar!";
		weapon.slotpriority 0;
		weapon.slotnumber 1;

		hdweapon.refid "cbr";
		tag "crowbar";

		+hdweapon.fitsinbackpack

		scale 0.75;

		radius 12;
		height 4;

		inventory.maxamount 3;

		+SpriteAngle
		SpriteAngle 180;

		+NoBlood
		+NoDamage
		health TELEFRAG_DAMAGE;
		painchance 256;
	}

	override void MarkPrecacheSounds( void )
	{
		MarkSound( "crowbar/swing" );
		MarkSound( "crowbar/crit" );
		MarkSound( "weapon/smack" );
	}

	override bool CanCollideWith( Actor other, bool passive )
	{
		// collide with bullets
		return super.CanCollideWith( other, passive ) || ( bShootable && other.bMissile );
	}

	override bool AddSpareWeapon( Actor newOwner ) { return AddSpareWeaponRegular( newOwner ); }
	override HDWeapon GetSpareWeapon( Actor newOwner, bool reverse, bool doSelect ) { return GetSpareWeaponRegular( newOwner, reverse, doSelect ); }

	override double WeaponBulk( void ) { return 64; }
	override double GunMass( void ) { return 12; }

	override string, double GetPickupSprite() { return "CBARA0", 1.; }

	override string GetHelpText( void )
	{
		return
		WEPHELP_FIRE .. " Swing\n"..
		WEPHELP_ALTFIRE .. " Place\n"
		;
	}

	private bool attached;

	private sector blockedSector;
	private bool blockedSectorWasSilent;

	void AttachCrowbar( sector blocked, bool onFloor )
	{
		attached = true;

		if( blocked )
		{
			blockedSector = blocked;

			if( // selected plane has sector effect thinker
				( onFloor && blocked.floordata ) ||
				( !onFloor && blocked.ceilingdata )
			)
			{
				blockedSectorWasSilent = bool( blocked.flags & sector.SECF_SILENTMOVE );
				if( !blockedSectorWasSilent ) blocked.flags |= sector.SECF_SILENTMOVE;
			}
		}

		spriteAngle = onFloor ? 0 : 225;

		bNoGravity = true;
		bWallSprite = true;
		bActLikeBridge = true;

		bShootable = true;

		// do not the dragging
		mass = int.MAX;
	}

	void DetachCrowbar( void )
	{
		if( !attached ) return;
		attached = false;

		if( blockedSector )
		{
			if( !blockedSectorWasSilent )
				blockedSector.flags &= ~sector.SECF_SILENTMOVE;

			blockedSector = null;
		}

		SpriteAngle = 180;

		bNoGravity = false;
		bWallSprite = false;
		bActLikeBridge = false;

		bShootable = false;

		mass = default.mass;
	}

	override void ActualPickup( Actor other, bool silent )
	{
		DetachCrowbar();
		super.ActualPickup( other, silent );
	}

	override void OnDestroy()
	{
		DetachCrowbar();
		super.OnDestroy();
	}

	void CrowbarAltFire( flinetracedata data )
	{
		sector blocked;
		vector3 newPos;
		bool place = false;
		bool onFloor = false;

		double newAngle;

		switch( data.HitType )
		{
		case Trace_HitWall:
			blocked = data.HitSector;

			let hitLine = data.HitLine;

			let delta = hitLine.delta;
			if( data.LineSide == Line.front )
				delta = -delta;

			let hitNormal = ( -delta.y, delta.x ).Unit();

			newPos = data.HitLocation + ( hitNormal * radius * 1.3 );
			newAngle = VectorAngle( hitNormal.x, hitNormal.y ) - 90;

			let blockedFloorZ = blocked.floorPlane.ZAtPoint( data.HitLocation.xy );
			let blockedCeilZ = blocked.ceilingPlane.ZAtPoint( data.HitLocation.xy );

			let blockedHeight = blockedCeilZ - blockedFloorZ;

			if( newPos.z >= min( blockedCeilZ, ( blockedHeight * 0.7 ) + blockedFloorZ ) )
			{
				newPos.z = blockedCeilZ - height;
				place = true;
			}
			else if( newPos.z <= max( blockedFloorZ, ( blockedHeight * 0.3 ) + blockedFloorZ ) )
			{
				newPos.z = blockedFloorZ;
				onFloor = true;
				place = true;
			}

			break;

		case Trace_HitCeiling:
		case Trace_HitFloor:
			blocked = data.HitSector;
			onFloor = data.HitType == Trace_HitFloor;

			if( onFloor ? blocked.floorPlane.isSlope() : blocked.ceilingPlane.isSlope() ) break;

			let hitPos = data.HitLocation;

			let nearestLine = -1;
			let nearestDist = double.Infinity;
			let nearestVert = ( 0, 0 );

			// find nearest line
			for( int i = 0; i < blocked.lines.Size(); i++ )
			{
				let lll = blocked.lines[ i ];
				let other = lll.frontsector == blocked ? lll.backsector : lll.frontsector;
				if( other == blocked ) continue;

				// math...........................
				let delta = lll.delta;
				let fact = ( delta dot ( hitPos.xy - lll.v1.p ) ) / ( delta dot delta );
				let nearVert = lll.v1.p + delta * fact;

				let blockedFloorZ = blocked.floorPlane.ZAtPoint( nearVert );
				let blockedCeilZ = blocked.ceilingPlane.ZAtPoint( nearVert );

				let otherFloorZ = double.Infinity;
				let otherCeilZ = -double.Infinity;

				if( other )
				{
					otherFloorZ = other.floorPlane.ZAtPoint( nearVert );
					otherCeilZ = other.ceilingPlane.ZAtPoint( nearVert );
				}

				if( onFloor
					? ( blockedFloorZ < otherFloorZ || blockedFloorZ > otherCeilZ )
					: ( blockedCeilZ  > otherCeilZ  || blockedCeilZ < otherFloorZ )
				)
				{
					delta = nearVert - hitPos.xy;
					let nearDist = delta dot delta;

					if( nearDist < nearestDist )
					{
						nearestLine = i;
						nearestDist = nearDist;
						nearestVert = nearVert;
					}
				}
			}

			if( nearestLine < 0 || nearestDist > CrowbarRangeSqr) break;

			let lll = blocked.lines[ nearestLine ];

			delta = lll.delta;
			if( lll.frontsector == blocked )
				delta = -delta;

			hitNormal = ( -delta.y, delta.x ).Unit();

			newAngle = VectorAngle( hitNormal.x, hitNormal.y ) - 90;
			newPos.xy = nearestVert + ( hitNormal * radius * 1.3 );

			if( onFloor )
				newPos.z = blocked.floorPlane.ZAtPoint( nearestVert );
			else
				newPos.z = blocked.ceilingPlane.ZAtPoint( nearestVert ) - height;

			place = true;

			break;

		case Trace_HitNone:
		default:
			break;
		}

		if( place )
		{
			let cbr = NHDACrowbar( Spawn( "NHDACrowbar", newPos ) );

			if( owner.Distance3DSquared( cbr ) <= CrowbarRangeSqr )
			{
				cbr.angle = newAngle;
				cbr.AttachCrowbar( blocked, onFloor );

				Amount -= 1;
				GetSpareWeapon( owner );
			}
			else cbr.Destroy();
		}
	}


	action void MeleeAttack( double dmg )
	{
		// ripped from HD fist code
		// TODO: make this suck less
		flinetracedata punchline;
		bool hit = linetrace(
			angle, 48, pitch,
			TRF_NOSKY,
			offsetz:height-12,
			data:punchline
		);
		if( !hit ) return;

		// actual puff effect if the shot connects
		LineAttack( angle, 48, pitch, punchline.hitline ? ( countinv( "PowerStrength" ) ? random( 50, 120 ) : random( 5, 15 ) ) : 0, "none",
			countinv( "PowerStrength" ) ? "BulletPuffMedium" : "BulletPuffSmall",
			flags:LAF_NORANDOMPUFFZ|LAF_OVERRIDEZ,
			offsetz: height - 12
		);

		let punchee = punchline.hitactor;

		if( !punchee )
			HDF.Give( self, "WallChunkAmmo", 4 );

		// charge!
		if( punchee )
			dmg += HDMath.TowardsEachOther( self, punchee ) * 2;
		else
			dmg += vel.Length() * 2;

		// come in swinging
		let onr = hdplayerpawn( self );
		if( onr )
		{
			int iy = max( abs( player.cmd.pitch ), abs( player.cmd.yaw ) );

			if( iy > 0 ) iy /= 6;
			else if( iy < 0 ) iy /= 3;

			dmg += min( abs( iy ), dmg * 0.7 );
		}

		// shit happens
		dmg *= frandom( 0.8, 1.2 );

		// other effects
		if(
			onr
			&&punchee
			&&!punchee.bdontthrust
			&&(
				punchee.mass < 200
				||(
					punchee.radius * 2 < punchee.height
					&& punchline.hitlocation.z > punchee.pos.z + punchee.height * 0.6
				)
			)
		){
			double iyaw = player.cmd.yaw * ( 65535. / 360. );
			if( abs( iyaw ) > ( 0.5 ) )
				punchee.A_SetAngle( punchee.angle - iyaw * 100, SPF_INTERPOLATE );

			double ipitch = player.cmd.pitch * ( 65535. / 360. );
			if( abs( ipitch ) > ( 0.5 * 65535 / 360 ) )
				punchee.A_SetPitch( punchee.angle + ipitch * 100, SPF_INTERPOLATE );
		}

		// headshot lol
		if(
			punchee
			&& !punchee.bnopain
			&& punchee.health > 0
			&& !( punchee is "HDBarrel" )
			&& punchline.hitlocation.z > punchee.pos.z + punchee.height * 0.75
		){
			if( hd_debug ) A_Log( "HEAD SHOT" );
			hdmobbase.forcepain( punchee );
			dmg *= frandom( 1.1, 1.8 );
		}

		if( hd_debug ){
			string pch = "level";
			if( !!punchee ) pch = punchee.getclassname();
			A_Log( string.format( "Hit %s for %i damage!", pch, dmg ) );
		}
		if( punchee && ( dmg * 2 > punchee.health ) ) punchee.A_StartSound( "misc/bulletflesh", CHAN_AUTO );
		if( punchee ) punchee.damagemobj( self, self, int( dmg ), "SmallArms0" );

		if( !punchee ) doordestroyer.destroydoor( self, dmg * 0.3, dmg * 0.03, 48, height - 12, angle, pitch );
	}

	double charge;

	states
	{
	spawn:
		CBAR A -1;
		stop;

	pain:
	crush:
		CBAR A 0
		{
			// TODO: better pain sound
			invoker.A_StartSound( "weapon/smack" );
			invoker.DetachCrowbar();
		}
		goto spawn;

	select0:
		CRWB A 0;
		goto select0small;

	deselect0:
		CRWB A 0;
		goto deselect0small;

	ready:
		CRWB A 1 A_WeaponReady();
		goto readyend;

	// TODO: recoil, stamina drain, faster swing when zerked ( needs new sprites! )
	fire:
	swing:
		CRWB BCD 2;
	swinghold:
		TNT1 A 1
		{
			// might do away with the whole charge mechanic...
			invoker.charge = min( invoker.charge + 1. / 3., 10 );
		}
		TNT1 A 0 A_JumpIf( PressingFire(), "swinghold" );
		CRWB EFGHI 1;
		CRWB J 1
		{
			A_StartSound( "crowbar/swing", CHAN_WEAPON );
			if( invoker.charge >= 8 ) A_StartSound( "crowbar/crit", 9 );
		}
		CRWB KL 1;
		CRWB M 1 MeleeAttack( 50 + 3 * invoker.charge );
		CRWB NOP 1;
		TNT1 A 8 { invoker.charge = 0; }
		CRWB DCB 3;
		goto ready;

	altfire:
	place:
		CRWB BCD 2;
	placehold:
		TNT1 A 1 A_WeaponBusy;
		TNT1 A 0 A_JumpIf( PressingAltFire(), "placehold" );
		TNT1 A 0
		{
			flinetracedata data;
			linetrace(
				angle, CrowbarRange, pitch, flags:0,
				offsetz:height - 8,
				data:data
			);

			invoker.CrowbarAltFire( data );
		}
		CRWB DCB 2;
		goto nope;
	}
}
