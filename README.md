I've used [*Old_Polish_Cars_v5* split dataset](https://drive.google.com/open?id=1kq3odh47lAAOK8MmeckHeCh1pTk6ga0i) to [train image recognition network with PyTorch](https://github.com/wojtekcz/ml_seminars/blob/master/wyklad_3_old_polish_cars_10classes/vanilla_pytorch_ios_app_model/transfer_learning_tutorial.ipynb), exported it to ONNX format and integrated into iOS app using CoreML and UI taken from [TensorFlow iOS example](https://github.com/tensorflow/tensorflow/tree/master/tensorflow/examples/ios/camera) for image recognition. 

I've used Google Colaboratory service to train the network. [Here there is a setup notebook](https://github.com/wojtekcz/ml_seminars/blob/master/wyklad_3_old_polish_cars_10classes/old_polish_cars-10classes_setup.ipynb) that can be used to install pytorch and download dataset to colab's virtual machine.

![](images/iphone6_spacegrey_portrait.png)
