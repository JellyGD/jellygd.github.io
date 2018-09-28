# Block的声明以及使用
block 顾名思义代码块，将同一逻辑的代码放在一块，方便维护和代码更加简洁紧凑，易于阅读,而且它比函数使用更方便，代码更美观.
block属性声明使用的是修饰符是copy，至于为什么会是copy接下来会讨论。本章会从简单的使用block，然后抽丝剥茧慢慢的深挖block的原理，知道了原理之后，才能够准确的判断问题和在开发中完善代码不会出坑。

## block 的定义
简单的使用block，可以先从block的定义来查看。

```
返回类型(^block名称)(形参列表) = ^(形参列表){

};

```
来看看block的调用时如何调用的

```
block名称(实参); // 简单快捷

// 一般我们定义block 都是当成property来使用的， 也有直接把block 当成参数来传递的。

```

可以通过`typedef <#returnType#>(^<#name#>)(<#arguments#>);` 来定义block。 可以看出 `returnType `是返回类型，`name `是block的名称，`arguments `则是形参列表，那么简单的使用则如下：

```
typedef void(^BlockName)(NSString *name); // 一般如果形参列表没有，则写 void， 否则会有编译警告

@property (nonatomic, copy) BlockName block; // 定义block属性。内存属性修饰符copy

// 调用block 则简单很多

if (self.block) { // 判断block 是否存在，存在才调用
	self.block(@"hello word");
}

// 外部可以对block进行赋值。

__weaktypeof(self) weakSelf = self; // 当前使用到了 weakself，接下来也会讲到，是用来解决循环引用问题的。
self.xxx.block = ^(NSString *name){
	weakSelf.titleLabel.text = name;
};

```

Block的使用，是不是很简单。 那么接下来复杂一点，带返回值的block；

```
typedef (NSString *)(^BlockName)(NSString *name); // 当前定义了一个返回值为NSString的BlockName的block。

@property (nonatomic, copy) BlockName block; // 定义block属性。内存属性修饰符copy

// 调用block 则简单很多

if (self.block) { // 判断block 是否存在，存在才调用
	
 NSString *name = self.block(@"hello word");
 console.log(@"%@", name);
}

// 外部可以对block进行赋值。

self.xxx.block = ^(NSString *name){
	return [NSString stringWithFormat:@"返回值 %@",name];
};

// 结果打印 返回值 hello word

```

带返回值的Block 也很简单对不对。 好了， 来个666的操作来一波哈~~  

```
GDBlockDemo.h

@interface GDBlockDemo : NSObject

@property (nonatomic, assign) NSInteger totalNum;

- (GDBlockDemo *(^)(NSUInteger num))addNum;

@end


GDBlockDemo.m

#import "GDBlockDemo.h"

@implementation GDBlockDemo

- (GDBlockDemo *(^)(NSUInteger num))addNum{
    return ^(NSUInteger num){
        self.totalNum += num;
        return self;
    };
}


@end

GDBlockDemo *gdDemo = [[GDBlockDemo alloc] init];
gdDemo.addNum(1).addNum(2).addNum(3);

```
这一波操作如何？ 看懂了没有呢？  这个叫**链式编程**哈~~~  链式编程这里不多讲， 有兴趣的可以跟我说哈~~

装逼装完了， 开始了解下原理性的东西了~~ 

## block的内存属性为什么是copy，能其他的吗？
那么内存属性是copy，肯定就要说下内存方面了，block在内存中是存放在什么位置呢? 接下来我们来查看下block存储的位置。

```
- (void)showBlockAddress{
    
    void(^block1)(void) = ^(){
        NSLog(@"block1");
    };
    NSLog(@"block1, %@",block1);
    
    NSUInteger index = 1;
    void(^block2)(void) = ^(){
        NSLog(@"block2 %lu",(unsigned long)index);
    };
    NSLog(@"block2, %@",block2);
    
    __block NSUInteger index2 = 1;
    void(^block3)(void) = ^(){
        index2 = 3;
    };
    NSLog(@"block3, %@",block3);
}

```

输入结果如下：

```
2018-09-28 02:04:20.543496+0800 Network[44601:1212691] block1, <__NSGlobalBlock__: 0x1075afb08>
2018-09-28 02:04:20.543661+0800 Network[44601:1212691] block2, <__NSMallocBlock__: 0x6000007e8930>
2018-09-28 02:04:20.543806+0800 Network[44601:1212691] block3, <__NSMallocBlock__: 0x6000007e5980>
```
可以看出第一个block 在全局区域，第二个跟第三个在堆区域中。 其实还有一个block的类型是在栈区域中的。

Block在内存中的位置分为三种类型`NSGlobalBlock`，`NSStackBlock`, `NSMallocBlock`。

	NSGlobalBlock：类似函数，位于text段；
	NSStackBlock：位于栈内存，函数返回后Block将无效；
	NSMallocBlock：位于堆内存。
	
`NSGlobalBlock `是block中没有引用外部变量的。

`NSStackBlock ` 是block在MRC的情况下 创建的block是放在栈区域的。 

`NSMallocBlock ` 是block在ARC的情况下，默认会将block从栈中复制到堆中，而MRC 需要手动的copy到堆中。

所以根据以上的情况，如果在ARC的情况下，property的内存修饰符是可以使用strong的，为什么一直惯用copy的原因，猜测只是保留了原有的习惯和告诉自己block是从栈中复制到堆中的。

## block是如何捕获值的呢？
在刚才的代码中，也看到了使用了`__block`来修饰变量，然后在`block`中就可以当前的变量做修改。如果加`__block`则只能对变量做引用。那么`__block`做了什么呢？ 

## block的原理是什么？

## block中遇到循环引用怎么解决？ 

## weakself 和 strongself

## typedef 是什么？

## 扩展阅读

### strong 和 copy 修饰符有什么不同？（深浅拷贝方面）







