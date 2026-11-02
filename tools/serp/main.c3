module serp_main;

import serp;
import serp_tool;

fn int main(String[] args)
{
	Command* app = serp_tool::build_tool();
	defer app.free();
	return app.execute(args);
}
