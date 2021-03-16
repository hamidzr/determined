# -*- coding: utf-8 -*-
"""dl-pytorch-lightning.ipynb

Automatically generated by Colaboratory.

Original file is located at
    https://colab.research.google.com/github/ariepratama/python-playground/blob/master/dl-pytorch-lightning.ipynb
"""

# !pip install pytorch-lightning
# !pip install torchtext

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.optim import Adam

from torchtext.datasets import IMDB
from torchtext.data import BucketIterator, Field
from pytorch_lightning.core.lightning import LightningModule
from pytorch_lightning import Trainer
from pytorch_lightning.loggers import TensorBoardLogger

text_field = Field(sequential=True, include_lengths=True, fix_length=200)
label_field = Field(sequential=False)

train, test = IMDB.splits(text_field, label_field)

text_field.build_vocab(train, vectors='glove.6B.300d')
label_field.build_vocab(train)

device = 'cuda' if torch.cuda.is_available() else 'cpu'
batch_size = 32

train_iter, test_iter = BucketIterator.splits(
    (train, test), 
    batch_size=batch_size, 
    device=device
)

class MyModel(LightningModule):
    def __init__(self, embedding, lstm_input_size=300, lstm_hidden_size=100, output_size=3):
        super().__init__()
        self.embedding = embedding
        self.lstm = nn.LSTM(lstm_input_size, lstm_hidden_size)
        self.lin = nn.Linear(lstm_hidden_size, output_size)
        self.loss_function = nn.CrossEntropyLoss()

    def forward(self, X: torch.Tensor):
        # X is vector of shape (batch, input, )
        # need to be permuted because by default X is batch first
        x = self.embedding[X].to(self.device).permute(1, 0, 2)
        x, _ = self.lstm(x)
        x = F.elu(x.permute(1, 0, 2))
        x = self.lin(x)
        x = x.sum(dim=1)
        return x

    def training_step(self, batch, batch_idx):
        x, y = batch.text[0].T, batch.label
        y_hat = self(x)
        loss = self.loss_function(y_hat, y)
        return dict(
            loss=loss,
            log=dict(
                train_loss=loss
            )
        )

    def configure_optimizers(self):
        return Adam(self.parameters(), lr=0.01)

    def train_dataloader(self):
        return train_iter

    def validation_step(self, batch, batch_idx):
        x, y = batch.text[0].T, batch.label
        y_hat = self(x)
        loss = self.loss_function(y_hat, y)
        return dict(
            validation_loss=loss,
            log=dict(
                val_loss=loss
            )
        )

    def val_dataloader(self):
        return test_iter

if __name__ == 'main':
    model = MyModel(text_field.vocab.vectors)

    logger = TensorBoardLogger('tb_logs', name='my_model')
    trainer = Trainer(
        gpus=1,
        logger=logger,
        max_epochs=3
    )
    trainer.fit(model)
