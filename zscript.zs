version "4.8"

#include "zscript/nicohda/crowbar.zs"

class Crowbar_Spawner : EventHandler{

override void CheckReplacement( ReplaceEvent Crowbar ){

 switch ( Crowbar.Replacee.GetClassName() ) {
        
    case 'Chainsaw'   :   if(!random(0,3))Crowbar.Replacement = "NHDACrowbar";
        break;
        
    }

    Crowbar.IsFinal = false;

  }

}
