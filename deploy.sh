#! /bin/bash

hexo clean && hexo generate && hexo deploy
#不行就多试几次！
export HEXO_ALGOLIA_INDEXING_KEY=1436d35fecfffdefe190dfbb8d8b0df7
hexo algolia
sleep 5
export HEXO_ALGOLIA_INDEXING_KEY=1436d35fecfffdefe190dfbb8d8b0df7
hexo algolia
sleep 5
export HEXO_ALGOLIA_INDEXING_KEY=1436d35fecfffdefe190dfbb8d8b0df7
hexo algolia
