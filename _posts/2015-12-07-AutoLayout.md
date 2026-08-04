---
layout:     post
title:      AutoLayout
date:       2015-11-20 10:14:20
author:     Jelly
summary:  	 AutoLayout是6.0以后开始特有的功能，目前基本上App都是从7.0开始适配，所以AutoLayout必须掌握的技能
categories: jekyll
tags:
 - Github
 - AutoLayout
 
---


###自定义View

系统的UIProgressView 是有一个固定的高度，但是在我们开发的过程中，也希望大小是固定的，那我们就应该重写intrinsicContentSize 这个方法

	-(CGSize)intrinsicContentSize{
    	return CGSizeZero;
	}
	
	
如果这个视图只有一个方向的尺寸设置了固有大小，那么为另一个方向的尺寸返回UIViewNoIntrinsicMetric/NSViewNoIntrinsicMetric。 需要注意的是，固有内容大小必须是独立于视图frame的。例如，不可能返回一个基于frame特定高宽比的固有内容大小。


###多行文本的固有内容大小

UILabel和NSTextField对于多行文本的固有内容大小是模糊不清的。文本的高度取决于线的宽度，这也是解决约束条件时需要弄清的问题。为了解决这个问题，这两个类都有一个叫做preferredMaxLayoutWidth的新属性，这个属性指定了线宽度的最大值，以便计算固有内容大小。

因为我们通常不能提前知道这个值，为了获得正确的值我们需要先做两步操作。首先，我们让自动布局做它的工作，然后用布局传递结果的frame更新给首选最大宽度，并且再次触发布局。
	
	- (void)layoutSubviews
	{
 	   [super layoutSubviews];

 	   myLabel.preferredMaxLayoutWidth = myLabel.frame.size.width;

 	   [super layoutSubviews];
	}
	
第一次调用[super layoutSubviews]是为了获得label的frame，而第二次调用是改变后更新布局。如果省略第二个调用我们将会得到一个NSInternalInconsistencyException的错误，因为我们改变了更新约束条件的布局传递，但我们并没有再次触发布局。