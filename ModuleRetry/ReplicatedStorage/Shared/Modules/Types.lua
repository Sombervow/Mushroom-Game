local Types = {}

export type PlayerData = {
    Spores: number,
    Gems: number,
    LastSave: number,
    Version: number,
    AssignedPlot: number?,
    SporeUpgradeLevel: number?,
    FastRunnerLevel: number?,
    PickUpRangeLevel: number?,
    FasterShroomsLevel: number?,
    ShinySporeLevel: number?,
    GemHunterLevel: number?
}

export type PlotInfo = {
    plotId: number,
    spawnPoint: Vector3?
}

export type PlayerStats = {
    Spores: number,
    Gems: number,
    AssignedPlot: number?,
    SporeUpgradeLevel: number?,
    FastRunnerLevel: number?,
    PickUpRangeLevel: number?,
    FasterShroomsLevel: number?,
    ShinySporeLevel: number?,
    GemHunterLevel: number?
}

export type CurrencyType = "Spores" | "Gems"

export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR"

return Types