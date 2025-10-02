local Constants = {}

Constants.MAX_PLOTS = 6
Constants.MAX_CURRENCY = 1000000000

Constants.CURRENCY_TYPES = {
    SPORES = "Spores",
    GEMS = "Gems"
}

Constants.LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

Constants.DATASTORE = {
    NAME = "PlayerData_v1",
    RETRY_ATTEMPTS = 3,
    RETRY_DELAY = 1
}

Constants.PLOT = {
    TEMPLATE_NAME = "PlotTemplate",
    SPAWN_PREFIX = "SpawnPoint",
    PLOT_PREFIX = "Plot_"
}

Constants.STORAGE = {
    MAX_SPORES_PER_AREA = 500,
    AREAS = {"Area1", "Area2", "Area3"}
}

return Constants