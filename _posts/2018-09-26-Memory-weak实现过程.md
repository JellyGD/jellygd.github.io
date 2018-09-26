
#  weak实现过程
weak修饰的对象，会在被修饰对象释放的时候，修饰对象会自动变成nil。
weak的出现主要是为了解决内存泄露问题。 那么我们分两个部分来说明。
# weak修饰的对象是如何解决循环引用造成的内存泄露的问题。
##  什么是循环引用？
循环引用就是，当A对象引用B对象，B对象间接或者直接的引用这A对象。导致两者对象的引用计数器一直不为0，无法调用dealloc方法。从而造成循环引用。
## 什么是内存泄露？
内存泄露，则是当前的对象在对象的生命周期之外存活着。也就是说，当前的对象在该释放的时候，没有释放，从而一直霸占着内存。

说完这个，来看下如何解决循环引用的问题。
## 解决循环引用
weak的对象修饰符是不会对持有的对象做引用计数器+1的操作的。
weak 只是创建了一个指向对象的弱引用，weak弱引用是不能持有对象的，如果该对象在废弃的时候，则此弱引用自动失效并处于nil被赋值的状态。
### 扩展阅读 weakSelf 和 strongSelf
# weak是如何实现的？
weak实现分成三个步骤，创建一个weak弱引用对象、读取weak弱引用对象和在对象释放的时候weak弱引用变成nil。
## weak修饰的对象，在创建的时候做了什么?
weak修饰的对象相当于一下的生成方法。

```
NSObject *obj = [[NSObject alloc] init];
_weak obj1 = obj;

```
在创建weak弱引用对象的时候步骤如下：

	1、通过runtime调用objc_initWeak() 创建Weak表，Weak表存储着弱引用对象的地址和对象地址。（对象地址为key，弱应用对象地址为Value）;
	2、weak表 是一个二维数组，Key是所指对象的地址，Value是weak指针的地址（这个地址的值是所指对象的地址）数组。
	3、调用objc_storeWeak(&obj1,obj);
	
## weak修饰的对象，在读取的时候做了什么？
在使用weak对象的时候，是通过调用objc_loadWeakRetained方法来获取的。
可以通过Xcode设置，Debug >> Debug Workflow >> Always show Disassembly 来查看会堆栈信息。
```
     0x12e1ac4c5 <+101>: movq   %rcx, %rdi
    0x12e1ac4c8 <+104>: movq   %rcx, -0x48(%rbp)
    0x12e1ac4cc <+108>: callq  0x12e1b0248               ; symbol stub for: objc_storeWeak
->  0x12e1ac4d1 <+113>: movq   -0x48(%rbp), %rdi
    0x12e1ac4d5 <+117>: movq   %rax, -0x50(%rbp)
    0x12e1ac4d9 <+121>: callq  0x12e1b022a               ; symbol stub for: objc_loadWeakRetained
    0x12e1ac4de <+126>: movq   %rax, %rcx
    0x12e1ac4e1 <+129>: leaq   0x5e10(%rip), %rdi        ; @"weakObject = %@"
```
通过注释，可也看出weak指针的获取是通过objc_loadWeakRetained这个函数来获取的，并非直接获取weak指针。
objc_loadWeakRetained 中有引用计数器表自旋锁（sprinLock），所以 weak修饰的的对象是线程安全的。
## weak修饰的对象，在释放的时候做了什么？
weak修饰的对象，在对象释放的时候会自动变成nil，会调用接下来的几个步骤：

	1、object在release的时候 引用计数器减1，当达到0 的时候，对象释放。
	2、调用 当前对象的dealloc，然后调用父类的Dealloc，直到调用NSObject的dealloc方法。
	3、NSObject的dealloc 会调用 objc_rootDealloc方法。
	4、objc_rootDealloc => objc_despose() 然后调用 objc_desposeInstance();
	5、然后调用objc_clear_deallocating();
	6、调用objc_storeWeak(&objc1); 将weak弱引用对象变成nil。
    
### 扩展阅读 Association通过分类添加的对象是什么时候释放的？ 


### [扩展阅读 Weak修饰的弱引用对象是不是线程安全的？](http://jellygd.github.io/2018/09/26/%E6%89%A9%E5%B1%95%E9%98%85%E8%AF%BB-weak%E7%BA%BF%E7%A8%8B%E5%AE%89%E5%85%A8/)