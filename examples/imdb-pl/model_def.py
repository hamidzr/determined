from determined.pytorch._lightning import PLAdapter
from determined.pytorch import PyTorchTrialContext, DataLoader
import imdb


class IMDBTrial(PLAdapter):
    def __init__(self, context: PyTorchTrialContext):
        pass
