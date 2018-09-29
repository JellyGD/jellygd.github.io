# Block的声明以及使用
block 顾名思义代码块，将同一逻辑的代码放在一块，方便维护和代码更加简洁紧凑，易于阅读,而且它比函数使用更方便，代码更美观.
block属性声明使用的是修饰符是copy，至于为什么会是copy接下来会讨论。本章会从简单的使用block，然后抽丝剥茧慢慢的深挖block的原理，知道了原理之后，才能够准确的判断问题和在开发中完善代码不会出坑。

## block 的定义
简单的使用block，可以先从block的定义来查看。

```objc
返回类型(^block名称)(形参列表) = ^(形参列表){

};

```
来看看block的调用时如何调用的

```objc
block名称(实参); // 简单快捷

// 一般我们定义block 都是当成property来使用的， 也有直接把block 当成参数来传递的。

```

可以通过`typedef <#returnType#>(^<#name#>)(<#arguments#>);` 来定义block。 可以看出 `returnType `是返回类型，`name `是block的名称，`arguments `则是形参列表，那么简单的使用则如下：

```objc
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

```objc
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

```objc
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

```objc
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
block的定义是 带有自动变量值的匿名函数。  带有自动变量值说的就是截获自动变量值。

```objc
#import <Foundation/Foundation.h>

- (void)testBlock {
    int val = 10;
    const char *fmt = "val = %d\n";
    void (^block)(void) = ^(){
        printf(fmt,val);
    };
    val = 100;
    fmt = "val已经改变 = %d\n";
    block();
    
}

```
上一句的代码的输出结果是

`val = 10`

执行的结果并不是`val已经改变 = 100`，而是执行block语法时自动变量的瞬间值，因为这些值（fmt`val = %d\n` ,val`10`）被保存（截获），从而在执行块中使用。 


### __block说明符的作用
自动变量值被截获只能保存执行Block语法的瞬间值，保存后就不能改写改值。在之前的代码中，也看到了使用了`__block`来修饰变量，然后在`block`中就可以当前的变量做修改。如果不加`__block`则只能对变量做引用。 

如果不加block 是不是全部都不能修改呢？ 来看下接下来的代码 有没有问题？ 

```objc

- (void)testBlockArray{
    NSMutableArray *array = [NSMutableArray array];
    void (^block)(void) = ^(){
        NSObject *obj = [[NSObject alloc] init];
        [array addObject:obj];
        NSLog(@"block array = %@",array);
    };
    NSLog(@"array = %@",array);
    block();
    NSLog(@"array block end= %@",array);
}

```

block是会自动截获变量， 但是截获的是类对象的结构体实例指针。 

**注意**

block截获自动变量的方法并没有实现对C语言数组的截获。

## block的原理是什么？
block通过支持block的编译器，含有Block语法的源代码转换为一般C语言编译器能够处理的源代码。并做为C语言的源代码被编译。

```C

struct __block_impl {
    void *isa; // 指向所属类的指针，也就是block的类型
    int Flags; // 标志变量，在实现block的内部操作时会用到
    int Reserved; // 保留变量
    void *FuncPtr; // block执行时调用的函数指针
};
// Runtime copy/destroy helper functions (from Block_private.h)

struct __BlockSImple__simpleGD_block_impl_0 {
    struct __block_impl impl; // block的结构体
    struct __BlockSImple__simpleGD_block_desc_0* Desc; // 内存相关 开辟内存控件的大小
    // 结构体构造函数
    __BlockSImple__simpleGD_block_impl_0(void *fp, struct __BlockSImple__simpleGD_block_desc_0 *desc, int flags=0) {
        impl.isa = &_NSConcreteStackBlock; // Block 生成是在栈上的。
        impl.Flags = flags;
        impl.FuncPtr = fp;
        Desc = desc;
    }
};
// 方法的真正操作的位置。
static void __BlockSImple__simpleGD_block_func_0(struct __BlockSImple__simpleGD_block_impl_0 *__cself) {
    printf("block"); }

static struct __BlockSImple__simpleGD_block_desc_0 {
    size_t reserved; // 内存区域
    size_t Block_size; // 大小
} __BlockSImple__simpleGD_block_desc_0_DATA = { 0, sizeof(struct __BlockSImple__simpleGD_block_impl_0)};

static void _I_BlockSImple_simpleGD(BlockSImple * self, SEL _cmd) {
    // 定义Block
    void (*blk)(void) = ((void (*)())&__BlockSImple__simpleGD_block_impl_0((void *)__BlockSImple__simpleGD_block_func_0, &__BlockSImple__simpleGD_block_desc_0_DATA));
    // 执行Block
    ((void (*)(__block_impl *))((__block_impl *)blk)->FuncPtr)((__block_impl *)blk);

     // 简化下
    struct __BlockSImple__simpleGD_block_impl_0 tmp = __BlockSImple__simpleGD_block_impl_0(__BlockSImple__simpleGD_block_func_0,&__BlockSImple__simpleGD_block_desc_0_DATA);
    /*
     * __BlockSImple__simpleGD_block_impl_0 通过构造函数 可以得知
     * impl.FuncPtr = __BlockSImple__simpleGD_block_func_0;
     * Desc = &__BlockSImple__simpleGD_block_desc_0_DATA;
     */
     
    struct__BlockSImple__simpleGD_block_impl_0 *blk = &tmp;
    
    (*blk -> impl.FuncPtr)(blk); // 函数指针调用函数
}


```
clang后，再对代码进行简化，可以看出会比较简单。 主要来说， 是数据怎么去做截获的。 

先给个结论：**在执行Block语法时，Block语法表达式锁使用的自动变量值被保存到Block的结构体实例中。**

接下来看下`clang`下简单的代码：

```objc
NSUInteger index = 1;
void(^block2)(void) = ^(){
    NSLog(@"block2 %lu",(unsigned long)index);
};
    
```
clang后得到的简化代码如下：

```C

```


## block中遇到循环引用怎么解决？ 

首先先了解下， 什么时候循环引用，（retain cycle）。

Object 决定是否会被释放的条件是 retainCount(引用计数器) 为 0; 在对Object持有操作的时候（strong,retain,copy），会对对象的引用计数器加1，从而让Object对象不会被释放。

根据这种情况，如果对象A持有对象B， 对象B 间接或直接的 持有对象A， 形成了一个引用环。 B的释放需要等待持有对象A调用release， 对象A又在等待着独享B的release 方法调用。 所以导致对象A 和 对象B 一直不释放。



## weakself 和 strongself

## typedef 是什么？

## 扩展阅读

### strong 和 copy 修饰符有什么不同？（深浅拷贝方面）







