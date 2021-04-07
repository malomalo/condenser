require 'test_helper'

class MediaCombinerTest < ActiveSupport::TestCase
  
  def setup
    super
    @env.register_postprocessor('text/css', Condenser::CSSMediaCombinerProcessor)
    @env.unregister_minifier('text/css')
  end
  
  test 'combine media queries' do
    file 'main.css', <<~CSS
      .test{
        display: block;
      }
      @media only screen and (max-width: 100px) {
        .test {
          display: inline-block;
        }
      }
      @media only screen and (max-width: 500px) {
        .test {
          display: inline;
        }
      }
      
      .test2{
        display: block;
      }
      @media only screen and (max-width: 100px) {
        .test2 {
          display: inline-block;
        }
      }
    CSS

    assert_exported_file 'main.css', 'text/css', <<~FILE
    .test{
      display: block;
    }



    .test2{
      display: block;
    }

    @media only screen and (max-width: 100px) {
      .test {
        display: inline-block;
      }

      .test2 {
        display: inline-block;
      }
    }@media only screen and (max-width: 500px) {
      .test {
        display: inline;
      }
    }
    FILE
  end
  
  test 'single line css' do
    file 'main.css', <<~CSS
      .test{display: block;} @media only screen and (max-width: 100px) {.test {display: inline-block;}}@media only screen and (max-width: 500px) {.test {display: inline;}}.test2{display: block;}@media only screen and (max-width: 100px) {.test2 {display: inline-block;}}
    CSS
    
    assert_exported_file 'main.css', 'text/css', <<~FILE
    .test{display: block;} .test2{display: block;}
    @media only screen and (max-width: 100px) {.test {display: inline-block;}.test2 {display: inline-block;}}@media only screen and (max-width: 500px) {.test {display: inline;}}
    FILE
  end
  
  
  test 'keyframes' do
    file 'main.css', <<~CSS
    .trobber {
    animation: throb 1s infinite;
    }
    @keyframes throb {
        0% {
            opacity: 1;
        }
        100%{
            opacity: 0;
        }
    }
    CSS

    assert_exported_file 'main.css', 'text/css', <<~FILE
    .trobber {
    animation: throb 1s infinite;
    }
    @keyframes throb {
        0% {
            opacity: 1;
        }
        100%{
            opacity: 0;
        }
    }
    FILE
  end
  

end
