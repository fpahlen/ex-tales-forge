/**
 * Starting State Schema for Merovingia Module
 * 
 * These interfaces define the structure of the "New Game" snapshot.
 * The game engine uses these to validate and process starting-state.json.
 * 
 * NOTE: This is a documentation/schema file, not runtime code.
 * The actual game engine may import or duplicate these types.
 */

// =============================================================================
// Core Types
// =============================================================================

export type Urgency = 'low' | 'medium' | 'high' | 'critical';
export type TensionIntensity = 'simmering' | 'active' | 'heated' | 'crisis';
export type DayPhase = 'dawn' | 'morning' | 'midday' | 'afternoon' | 'evening' | 'night';

// =============================================================================
// World Time
// =============================================================================

export interface WorldTime {
  /** Day of the current month (1-30) */
  day: number;
  /** Hour of the day (0-23) */
  hour: number;
  /** Named phase of the day */
  phase: DayPhase;
  /** Season at game start */
  season: 'spring' | 'summer' | 'autumn' | 'winter';
  /** Year in the reign of Clovis IV */
  year: number;
}

// =============================================================================
// NPC Starting Positions
// =============================================================================

export interface NPCStartingPosition {
  /** Unique identifier for this NPC */
  id: string;
  /** Display name */
  name: string;
  /** Reference to canonical documentation */
  canonical_ref: string;
  /** NPC category for filtering */
  category: 'baron' | 'ambassador' | 'court' | 'other';
  /** Current physical location */
  location: {
    /** Name of the location */
    name: string;
    /** Barony or region containing the location */
    region: string;
  };
  /** What's currently driving this NPC's behavior */
  current_concern: {
    /** Brief description of the concern */
    description: string;
    /** How urgent is this to the NPC */
    urgency: Urgency;
    /** What constraint limits their action on this concern */
    constraint?: string;
  };
  /** Brief note on their starting mood/stance */
  disposition?: string;
}

// =============================================================================
// Active Tensions
// =============================================================================

export interface ActiveTension {
  /** Unique identifier */
  id: string;
  /** NPCs or factions involved (array of IDs) */
  parties: string[];
  /** What the tension is about */
  description: string;
  /** Current intensity level */
  intensity: TensionIntensity;
  /** Reference to canonical source of this tension */
  canonical_ref: string;
  /** What could escalate this tension */
  escalation_trigger?: string;
  /** What could de-escalate this tension */
  resolution_path?: string;
}

// =============================================================================
// Rumors
// =============================================================================

export interface Rumor {
  /** Unique identifier */
  id: string;
  /** The rumor text as NPCs might share it */
  text: string;
  /** Where this rumor is primarily circulating */
  origin_region: string;
  /** How widely known is this rumor */
  spread: 'local' | 'regional' | 'kingdom-wide';
  /** Is this rumor true, false, or partially true */
  veracity: 'true' | 'false' | 'partial' | 'unknown';
  /** If veracity is discoverable, what's the canonical reference */
  truth_ref?: string;
}

// =============================================================================
// Starting State Root
// =============================================================================

export interface StartingState {
  /** Metadata about this starting state */
  meta: {
    /** Version of this starting state definition */
    version: string;
    /** Module ID this starting state belongs to (matches module.json id) */
    module_id: string;
    /** When this was last updated */
    last_updated: string;
    /** Brief description of when this represents */
    description: string;
  };
  
  /** World time at game start */
  world_time: WorldTime;
  
  /** All key NPC starting positions */
  key_npcs: NPCStartingPosition[];
  
  /** Active tensions between parties */
  active_tensions: ActiveTension[];
  
  /** Rumors circulating at game start */
  rumors: Rumor[];
}
