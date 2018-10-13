#  RunLoop
RunLoop跟内存之间的关系，在ARC的场景下，是依赖Autorelease来管理对象的释放的。 
Autorelease是由多个AutoreleasePage组成。每一个Page的大小都是4096字节，然后用双链表的方式连接在一起。

在没有手动干预AutoreleasePool的情况下，Autorelease对象是在当前的RunLoop迭代结束是释放的
而它能够释放的原因是系统在每个RunLoop迭代中都加入了自动释放池Push 和Pop.

``` objc
__weak id obj;
-(void)viewDidLoad{
    NSString *test = [NSString stringWithFormat:@"runLoop test"];
    obj = test;
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    NSLog(@"%s === %@",__func__,obj);
    
    NSLog(@"current runLoop = %@",[NSRunLoop currentRunLoop]);
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    NSLog(@"%s === %@",__func__,obj);
}

```
根据以上测试代码，得出输出结果：

```
-[DemoBaseViewController viewWillAppear:] === runLoop test
-[DemoBaseViewController viewDidAppear:] === (null)
```

在`viewWillAppear `的时候 obj 还存在， 在`viewDidAppear `的时候，obj就已经被系统废弃。

从而得出结论是：

>释放时机是基于`runloop`而不是作用域；
>
>通过autorelease pool手动干预释放；循环多次时当心要对autorelease进行优化,否则会造成内存紧张。
>
>离开做作用域的时候，只是会给当前的对象添加到Autoreleasepool中，等待 autoreleasepool pop 操作。
>
>runloop 会管理AutoreleasePool的创建 和 释放。 在RunLoop被创建的时候，AutoreleasePool 默认会被创建。
>runloop 在进入休眠的时候，会对之前的runloop做释放，然后重新创建新的AutoreleasePool。
>runloop 退出的时候，会对当前的AutoreleasePool 进行pop的操作。


