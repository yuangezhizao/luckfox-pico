// SPDX-License-Identifier: GPL-2.0-only

#include <linux/init.h>
#include <linux/module.h>

static int __init helloworld_init(void)
{
	pr_info("helloworld!\n");
	return 0;
}

static void __exit helloworld_exit(void)
{
	pr_info("helloworld bye\n");
}

module_init(helloworld_init);
module_exit(helloworld_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Luckfox");
MODULE_DESCRIPTION("Luckfox Pico external kernel module example");
MODULE_VERSION("V1.0");
