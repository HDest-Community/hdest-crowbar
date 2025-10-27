class NHDACrowbar : HDFist// 
{
    //this is for the door jamming mechanic
	const CrowbarRange = 72;
	const CrowbarRangeSqr = CrowbarRange ** 2;


    default{
		+ambush
		+WEAPON.MELEEWEAPON 
		+WEAPON.NOALERT 
	  //+WEAPON.NO_AUTO_SWITCH
		+nointeraction
		+hdweapon.fitsinbackpack
		
		scale 0.75;
		radius 12;
		height 4;

		weapon.selectionorder 100;
		weapon.slotpriority 0.2;
		weapon.slotnumber 1;
		obituary "%o got whacked in the head by %k's crowbar."; //"$OB_FIST";
		
		weapon.kickback 120;
		weapon.bobstyle "Alpha";
		weapon.bobspeed 2.6;
		weapon.bobrangex 0.1;
		weapon.bobrangey 0.5;
		tag "Crowbar";
		hdweapon.refid "cbr";
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
		WEPHELP_FIRE.." Swing\n"
		..WEPHELP_ALTFIRE.."  Lunge and swing\n"
		..WEPHELP_RELOAD.."  Kick and swing\n"
		..WEPHELP_UNLOAD.."  Jam into place\n"
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

	void CrowbarJam( flinetracedata data )
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

	action void MeleeAttack(double dmg){//copied from current HDFist code as of 01-21-23
		let punchrange=56.;//48+8
		if(hdplayerpawn(self))punchrange*=hdplayerpawn(self).heightmult;

		flinetracedata punchline;
		bool punchy=linetrace(
			angle,punchrange,pitch,
			TRF_NOSKY,
			offsetz:height*0.77,
			data:punchline
		);
		if(!punchy)return;

		//actual puff effect if the shot connects
		LineAttack(
			angle,
			punchrange,
			pitch,
			punchline.hitline?(int(frandom(5,15)*invoker.strength)):0,
			"none",
			(invoker.strength>1.5)?"BulletPuffMedium":"BulletPuffSmall",
			flags:LAF_NORANDOMPUFFZ|LAF_OVERRIDEZ,
			offsetz:height*0.78
		);

		if(!punchline.hitactor){
			HDF.Give(self,"WallChunkAmmo",1);
			if(punchline.hitline){		
			//damage sectors
		    A_StartSound("crowbar/hitwall",CHAN_AUTO);
		    A_Recoil(1+dmg/50);
            doordestroyer.destroydoor(self,frandom(16,frandom(16,72))*invoker.strength,frandom(0,frandom(dmg/10,dmg/5)*invoker.strength));
            doordestroyer.CheckDirtyWindowBreak(punchline.hitline,0.09+0.03*invoker.strength,punchline.hitlocation);
			}//breaks windows 3x better
			return;
		}
		actor punchee=punchline.hitactor;


		//charge!
		if(invoker.flicked)dmg*=1.5;
		else dmg+=HDMath.TowardsEachOther(self,punchee)*3;

		//come in swinging
		let onr=hdplayerpawn(self);
		double ptch=0.;
		double pyaw=0.;
		if(onr){
			ptch=deltaangle(onr.lastpitch,onr.pitch);
			pyaw=deltaangle(onr.lastangle,onr.angle);
			double iy=max(abs(ptch),abs(pyaw));
			if(pyaw<0)iy*=1.6;
			if(player.onground)dmg+=min(abs(iy)*5,dmg*3);
		}

		//shit happens
		dmg*=invoker.strength*frandom(1.,1.2);

		//other effects
		if(
			onr
			&&!punchee.bdontthrust
			&&(
				punchee.mass<200
				||(
					punchee.radius*2<punchee.height
					&& punchline.hitlocation.z>punchee.pos.z+punchee.height*0.6
				)
			)
		){
			if(abs(pyaw)>(0.5)){
				punchee.A_SetAngle(clamp(normalize180(punchee.angle-pyaw*100),-50,50),SPF_INTERPOLATE);
			}
			if(abs(ptch)>(0.5*65535/360)){
				punchee.A_SetPitch(clamp((punchee.angle+ptch*100)%90,-30,30),SPF_INTERPOLATE);
			}
		}

		let hdmp=hdmobbase(punchee);

		//headshot lol
		if(
			!punchee.bnopain
			&&punchee.health>0
			&&(
				!hdmp
				||!hdmp.bheadless
			)
			&&punchline.hitlocation.z>punchee.pos.z+punchee.height*0.75
		){
		    punchee.A_StartSound("crowbar/hitflesh",CHAN_AUTO);
			if(hd_debug)A_Log("HEAD SHOT");
			hdmobbase.forcepain(punchee);
			dmg*=frandom(1.1,1.8);
			if(hdmp)hdmp.stunned+=(int(dmg)>>2);
		}

		if(hd_debug)A_Log("Crowbar'd "..punchee.getclassname().." for "..int(dmg).." damage!");

		bool puncheewasalive=!punchee.bcorpse&&punchee.health>0;

		if(dmg*2>punchee.health)punchee.A_StartSound("crowbar/hitflesh",CHAN_AUTO);
		punchee.damagemobj(self,self,int(dmg),"melee");

		if(!punchee)invoker.targethealth=0;else{
			invoker.targethealth=punchee.health;
			invoker.targetspawnhealth=punchee.spawnhealth();
			invoker.targettimer=0;
			if(
				(
					punchee.bismonster
					||!!punchee.player
				)
				&&invoker.zerk
			){
				if(
					punchee.bcorpse
					&&puncheewasalive
				){
					A_StartSound("weapons/zerkding2",CHAN_WEAPON,CHANF_OVERLAP|CHANF_LOCAL);
					givebody(10);
					if(onr){
						onr.fatigue-=onr.fatigue>>2;
						onr.usegametip("\cfK I L L !");
					}
				}else{
					A_StartSound("weapons/zerkding",CHAN_WEAPON,CHANF_OVERLAP|CHANF_LOCAL);
				}
			}
		}
		
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
			invoker.A_StartSound( "crowbar/hitwall" );
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
		#### A 1{
			if(
				invoker.washolding
				&&player.cmd.buttons&(
					BT_ATTACK
					|BT_ALTATTACK
					|BT_RELOAD
					|BT_ZOOM
					|BT_USER1
					|BT_USER2
					|BT_USER3
					|BT_USER4
				)
			){
				setweaponstate("nope");
				return;
			}
			A_WeaponReady(WRF_ALL);
			invoker.flicked=false;
			invoker.washolding=false;
		}goto readyend;

    reload:
        #### A 0 A_JumpIf(hdplayerpawn(self).stunned>0,"nope");
	flick:
		#### B 1 offset(0,50);
		#### C 1 offset(0,36);
		#### DDDDDD 0 A_CustomPunch((int(ceil(invoker.strength))),1,CPF_PULLIN,"HDFistPuncher",36);
		#### DD 1 offset(0,38){invoker.flicked=true;}
		#### C 1 offset(0,42);
		#### B 1 offset(0,50);
		goto fire;

	// TODO: recoil, stamina drain, faster swing when zerked ( needs new sprites! )
	fire:
	#### A 0 A_JumpIf(hdplayerpawn(self).stunned>0,"nope");
	swing:
		CRWB BBCD 1;//faster prep
	swinghold:
		TNT1 A 1
		{
				
			let hdp=hdplayerpawn(self);
			let swingdmg = invoker.charge;

            //holding the crowbar ready tires you
            if(!random(0,99))hdp.fatigue+=1;
			invoker.charge = min( swingdmg + 1. / 3., 10 );
		
            //aborts swing if stunned or tired
			if(
				hdp.fatigue>HDCONST_SPRINTFATIGUE
				||hdp.stunned>0
			){  A_PlaySkinSound(SKINSOUND_GRUNT,"*usefail");
				setweaponstate("swing_end");
				return;
			}
		}
		TNT1 A 0 A_JumpIf( PressingFire()||PressingAltFire()||PressingReload(), "swinghold" );
		CRWB EFGHI 1;
		CRWB J 1
		{
			A_StartSound( "crowbar/swing", CHAN_WEAPON );
			if( invoker.charge >= 8 ) A_StartSound( "crowbar/crit", 9 );
			hdplayerpawn(self).fatigue+=1+invoker.charge/2;
			//swinging the crowbar exhausts your stamina,
			//heavy swings are more tiring than light swings
		}
		CRWB KL 1;
		CRWB M 1 MeleeAttack( 50 + 3 * invoker.charge );
		CRWB NOP 1;
		TNT1 A 6 A_JumpIf(invoker.zerk,1);//faster swings if zerked
		TNT1 A 2 {  invoker.charge = 0; 
		            if(PressingFire())setweaponstate("swinghold");
	            }
	swing_end:
		CRWB DDCB 1;//faster recovery
		#### A 0 A_JumpIf(PressingFire(),"nope");
		goto ready;

	altfire:
	#### A 0 A_JumpIf(hdplayerpawn(self).stunned>0,"nope");
	bodycheck:
		#### A 3{
			let hdp=hdplayerpawn(self);

			if(
				hdp.fatigue>HDCONST_SPRINTFATIGUE
				||hdp.stunned>0
				||hdp.strength<0.9
				||(
					!player.onground
					&&checkmove(pos.xy-(cos(angle),sin(angle))*4)
				)
			){
				setweaponstate("swing");
				return;
			}

			hdp.fatigue+=4;
			A_ChangeVelocity(
				hdp.strength*(invoker.zerk?8:6)/max(1.,hdp.overloaded),
				0,0,CVF_RELATIVE
			);
		}
		CRWB BCD 1;
		goto swinghold;
	
	firemode://two-handed weapon, can't grab
	    goto nope;
	
	unload:
	place:
		CRWB BCD 2;
	placehold:
		TNT1 A 1 A_WeaponBusy;
		TNT1 A 0 A_JumpIf( PressingUnload(), "placehold" );
		TNT1 A 0
		{
			flinetracedata data;
			linetrace(
				angle, CrowbarRange, pitch, flags:0,
				offsetz:height - 8,
				data:data
			);

			invoker.CrowbarJam( data );
		}
		CRWB DCB 2;
		goto nope;
	}
}
